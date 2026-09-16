#!/system/bin/sh
# Temporary first-boot collector for the M95 HIDL/healthd crash cascade.
# /cache is mounted by init.mt6797.rc before this service starts. Do not write
# /misc or any block device: para is the device's boot-control partition.

set -u

base=/cache/m95-fatal-capture
mkdir -p "$base"
chmod 0700 "$base"

# Bring-up workaround, runs before the framework starts.
#
# Every child cpuset comes up with an empty cpu list, and a task cannot be moved
# into an empty cpuset, so DisplayManagerService.setupSchedulerPolicies() throws
#   java.lang.IllegalArgumentException: Invalid argument: <tid>
#     at android.os.Process.setThreadGroupAndCpuset(Native Method)
# and system_server aborts on every start.
#
# The generic init.rc writes fixed masks like 0-7, but this is a deca-core
# MT6797 whose MTK hotplug has most cores offline by then (present 0-9, online
# 4-6,8-9). A child cpuset can only hold cpus its parent has, and the root
# cpuset tracks the online set, so those writes land empty.
#
# Copying the root's current list is NOT enough, and the first attempt at that
# only appeared to work because system_server won the race: whenever hotplug
# takes a cpu offline the kernel removes it from every cpuset, and a child that
# listed only offline cpus ends up empty again. Observed exactly that - the sets
# were repopulated, system_server started, and minutes later they read [] again
# with the same IllegalArgumentException back.
#
# So pin the topology first: turn MTK hotplug off, then bring up a fixed set of
# cores and fill the sets from it. With hps disabled nothing takes cores away
# again, so the sets stop decaying and system_server stays up through dex2oat.
#
# WHICH cores matters, and the first version of this got it wrong: it brought
# every present core online and left them there. The MT6797 is 4x A53 little +
# 4x A53 mid + 2x A72 big, and running all ten flat out through a dex2oat boot
# made the phone genuinely hot in the hand - dmesg showed the kernel limiter
# working at T=76300..76800 the whole time, which is SoC self-protection, not
# comfort. So: keep only the little cluster pinned, and explicitly park the two
# A72s, which are the dominant heat source. Boot is slower; the phone is not a
# frying pan. cpu0 cannot be offlined, so the set can never end up empty.
#
# The real thermal fix is separate and is not this file: the MTK thermal
# daemons were never started at all. See rootdir/init.m95.thermal.rc.
#
# This whole block is still a bring-up measure. It costs idle power and belongs
# in a proper init.m95.cpuset.rc with a hotplug-aware helper, not in the log
# collector. 3.18 has no cpuset_v2_mode (checked: kernel/cpuset.c has no such
# symbol), so a child cpuset's cpus_allowed is pruned for good when a listed
# cpu goes offline - which is why "just write the mask" does not work here.
echo 0 > /proc/hps/enabled 2>/dev/null || true
for _cpu in 0 1 2 3; do
    echo 1 > "/sys/devices/system/cpu/cpu$_cpu/online" 2>/dev/null || true
done
for _cpu in 8 9; do
    echo 0 > "/sys/devices/system/cpu/cpu$_cpu/online" 2>/dev/null || true
done

for _cpuset in foreground background top-app system-background restricted \
               foreground/boost; do
    [ -d "/dev/cpuset/$_cpuset" ] || continue
    cat /dev/cpuset/cpus > "/dev/cpuset/$_cpuset/cpus" 2>/dev/null || true
done

boot_id="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo unknown)"
dir="$base/$boot_id"
mkdir -p "$dir/tombstones"
chmod 0700 "$dir" "$dir/tombstones"

# Only replace the kept copy when the new dump actually has content. Boot b11
# ended with a 0-byte logcat.txt: logcat exited 0 with no output (logd not up
# yet, or already gone), and the unconditional mv overwrote the good copy.
capture_logcat() {
    /system/bin/logcat -b all -v threadtime -d > "$dir/logcat.txt.new" 2>&1
    if [ -s "$dir/logcat.txt.new" ]; then
        mv "$dir/logcat.txt.new" "$dir/logcat.txt"
        [ -s "$dir/logcat-first.txt" ] || cp "$dir/logcat.txt" "$dir/logcat-first.txt"
    else
        rm -f "$dir/logcat.txt.new"
    fi
}

# The kernel side is the reason this exists now: /proc/last_kmsg is the MTK ram
# console, only CONFIG_MTK_RAM_CONSOLE_DRAM_SIZE = 0x10000 (64 KiB), so it keeps
# roughly the last 13 seconds and never shows mtkfb/LCM/Mali probe. dmesg reads
# the kernel's own ring, which at this point still holds the start of the boot.
capture_dmesg() {
    /system/bin/dmesg > "$dir/dmesg.txt.new" 2>&1
    if [ -s "$dir/dmesg.txt.new" ]; then
        mv "$dir/dmesg.txt.new" "$dir/dmesg.txt"
        [ -s "$dir/dmesg-first.txt" ] || cp "$dir/dmesg.txt" "$dir/dmesg-first.txt"
    else
        rm -f "$dir/dmesg.txt.new"
    fi
}

# dmesg-first.txt is taken at post-fs, which is too early: the display and
# composer traffic happens around 20-30s, and the ring wraps in under a minute
# even at CONFIG_LOG_BUF_SHIFT=21. Keep untouched snapshots at fixed elapsed
# times so the interesting window survives regardless of how fast it rolls.
keep_dmesg_snapshot() {
    [ -s "$dir/dmesg.txt" ] || return 0
    [ -s "$dir/dmesg-$1.txt" ] && return 0
    cp "$dir/dmesg.txt" "$dir/dmesg-$1.txt"
}

capture_tombstones() {
    for tombstone in /data/tombstones/*; do
        [ -f "$tombstone" ] || continue
        cp "$tombstone" "$dir/tombstones/" 2>/dev/null || true
    done
}

{
    echo "boot_id=$boot_id"
    date -u '+started_utc=%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || true
    getprop ro.build.fingerprint 2>/dev/null || true
} > "$dir/metadata.txt"

# Init starts this after /cache is mounted. A short polling interval preserves
# the first abort/linker message even when init reaches its critical-restart
# threshold seconds later.
#
# Auto-return to recovery: adb does not work on the booted system (LOS16 adbd
# drives FunctionFS over AIO, and this 3.18 kernel's drivers/usb/gadget/f_fs.c
# has no AIO at all), so the only way to read these files is TWRP, whose stock
# kernel does have working adb. After the window below the collector reboots
# into recovery by itself instead of needing a hand on the power button.
# One-shot: the stamp keeps a recovery boot from turning into a reboot loop.
window=${M95_CAPTURE_WINDOW:-150}
stamp="$base/.autorecovery-done"

elapsed=0
while true; do
    capture_logcat
    capture_dmesg
    capture_tombstones
    sleep 1
    elapsed=$((elapsed + 1))
    case "$elapsed" in
        30|45|60|90) keep_dmesg_snapshot "${elapsed}s" ;;
    esac
    if [ "$elapsed" -ge "$window" ] && [ ! -f "$stamp" ]; then
        : > "$stamp"
        sync
        /system/bin/reboot recovery
    fi
done
