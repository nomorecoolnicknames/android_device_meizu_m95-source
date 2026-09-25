#!/system/bin/sh
# Keep the Android cpusets usable on this deca-core MT6797.
#
# THE PROBLEM, as measured on the device rather than reasoned about:
#
#   /sys/devices/system/cpu/online   0-2,4-9      <- nine cores running
#   /dev/cpuset/cpus                 4            <- the ROOT cpuset
#   foreground / background / top-app / system-background / restricted
#                                    4
#
# Every process in the system pinned to a single A53 while nine cores idled.
# That is where the load average of 20 came from, and it makes the phone hotter
# rather than cooler, because the same work takes far longer.
#
# WHY IT HAPPENS: cgroup v1 removes a cpu from cpus_allowed when hotplug parks
# it and never puts it back when it returns. So the root set decays
# monotonically, independent of how many cores are actually online, and the
# fixed masks the generic init.rc writes (background=0, system-background=0-3,
# top-app=0-7) get intersected down to whatever little is left. This kernel has
# no cpuset_v2_mode - checked, no such symbol in kernel/cpuset.c - so nothing
# preserves the configured mask.
#
# WHAT THIS DOES: rewrites the root set from the actual online mask, then
# copies it down into the children. Fixing the root is the part that matters;
# an earlier version of this script only did the children and achieved nothing,
# because you cannot widen a child beyond a parent that has itself collapsed.
#
# WHY A LOOP: the decay is fast. Measured, a freshly written set lost two cores
# in eight seconds. A one-shot at `on boot` was tried and the sets were back to
# cpu4 a minute later; triggering on sys.boot_completed is no good either,
# because while anything earlier in the boot is broken that property never
# arrives. Five seconds keeps the sets wide for most of every interval and
# costs a read, a few small writes and a sleep.
#
# WHAT THIS DELIBERATELY DOES NOT DO: it does not touch /proc/hps/enabled and
# does not force cores online. An earlier bring-up workaround, in
# m95-fatal-capture.sh, disabled hotplug and pinned all ten cores so the sets
# could never empty - that cooked the phone. It is also no longer needed: the
# abort it existed to dodge,
#   DisplayManagerService.setupSchedulerPolicies() -> IllegalArgumentException
# has zero hits across a full boot on this build.
#
# THE REAL FIX (done 2026-09-06, kernel/cpuset.c): backport of android-3.18
# "cpuset: Make cpusets restore on hotplug" -- the kernel keeps the mask the
# user wrote (cpus_requested) and re-derives cpus_allowed from it on every
# hotplug event, so a returning core is put back and a set that names cpu0
# (which never goes offline) can never be empty again. Writes may now name
# offline cpus (only non-present cpus are rejected), so this script writes the
# PRESENT set once per pass instead of chasing the online mask. It is kept as
# belt-and-braces for the kernel-less recovery boot and for any set init.rc
# creates from a shrunken root copy.
#
# The root cpuset is read-only on this kernel (update_cpumask: -EACCES for
# top_cpuset; it tracks cpu_active_mask by itself), so it is not written.

set -u

# Performance / thermal profile, off unless persist.vendor.m95.perfprofile=1
# (rootdir/m95-perfprofile.sh, meizu-fleet/designs/M95_PERF_PROFILE_20260925.md).
# Read once here: set the property and reboot. When it is on, the profile owns
# the tzcpu table (thermal_once is skipped) and narrows foreground. The
# property survives a reflash, so a vendor image without the file must still
# boot: `.` on a missing file exits a non-interactive shell (POSIX special
# builtin) -- this script would die before switching hps off below.
PERFPROFILE=$(/vendor/bin/getprop persist.vendor.m95.perfprofile 2>/dev/null)
if [ "$PERFPROFILE" = 1 ] && [ -r /vendor/bin/m95-perfprofile.sh ]; then
    . /vendor/bin/m95-perfprofile.sh
else
    PERFPROFILE=
fi

# BRING-UP (2026-09-06): MTK hps hotplug is switched OFF and a fixed little
# cluster is pinned. Two reasons, both measured on the R bring-up:
#  1. kernel panic "BUG: failure at lib/list_debug.c:66/__list_del_entry()" in
#     migration/0 (cpu_stopper_thread) right after "CPU0: shutdown" by
#     hps_main -- a stop_machine vs hotplug race that the cpuset restore
#     backport makes far more likely (every hotplug event now migrates tasks);
#  2. thermal_zone1 at 82-87 C during first-boot dexopt with the MTK thermal
#     daemons not running yet (linker failures), i.e. no userspace throttling.
# cpu0-3 (A53 LITTLE) online, 4-9 (A53 mid + A72 big) offline. Slow but safe;
# revisit together with the thermal daemons and a hotplug-safe kernel.
#
# 2026-09-11 (A13 GSI, kernel #140): hps stays OFF (no dynamic hotplug, so the
# stop_machine race of reason 1 never gets an event to race on), but all ten
# cores are brought online once and left alone. Measured on the device:
# 10 min with 0-9 online, load ~13 -> steady, mtktscpu 63 C, thermald +
# thermalloadalgod running, WDT kicks every 5 s (the kicker was also fixed to
# survive hotplug, drivers/watchdog/mediatek/wdk). UI on 4 LITTLE cores was
# visibly sluggish; with A72 at 2.3 GHz it is not.
echo 0 > /proc/hps/enabled 2>/dev/null || true
for _cpu in ${PP_BOOT_CPUS:-1 2 3 4 5 6 7 8 9}; do
    echo 1 > "/sys/devices/system/cpu/cpu$_cpu/online" 2>/dev/null || true
done

# CPU thermal target (FACT 2026-09-13, FLYME13_KERNEL_PLAN.md §10.6): the vendor
# thermal daemon programs mtktscpu trips with cpu_adaptive_0/1 at 58/57 C, and in
# mtk_ts_cpu.c the trip bound to cpu_adaptive_N *is* the ATM target Tj -> the SoC
# is power-capped from 58 C, i.e. always (idle Tj ~60 C): little cluster cut to
# 1222 MHz, mid to 1625, games throttle right at launch.  MTK stock targets are
# ~85 C; the 110 C sysrst trip stays.  The daemon may rewrite the table on scene
# changes, so it is re-asserted from the patrol loop below.
TZCPU=/proc/driver/thermal/tzcpu
thermal_once() {
    [ -w "$TZCPU" ] || return 0
    grep -q 'trip_1=85000 0 cpu_adaptive_0' "$TZCPU" && return 0
    echo "10 110000 0 mtktscpu-sysrst 85000 0 cpu_adaptive_0 80000 0 cpu_adaptive_1 65000 0 no-cooler 63000 0 no-cooler 60000 0 no-cooler 55000 0 no-cooler 50000 0 no-cooler 45000 0 no-cooler 40000 0 no-cooler 40" > "$TZCPU" 2>/dev/null || true
}

# PER-SET MASKS (Android 13 port, M95_PREFLASH_PERF.md §4). Until now every
# set got the full present mask, background included. On this kernel that
# leaves background apps nothing that ranks them below the UI: no uclamp and
# no schedtune (neither is in the 3.18 .config), and A13 init.rc creates
# /dev/cpuctl/background without touching cpu.shares (init.rc:131-178), so a
# cached app syncing or unpacking competes with the top app on every core,
# the A72 pair included, at equal CFS weight. A13 itself says the device must
# set the masks (init.rc:333-335: "the device's init.rc must actually set the
# correct cpus"). The cpuset is the one isolation mechanism left here.
#
#   background, restricted  -> 0-3, the A53 LITTLE cluster (cpu_capacity 304;
#       4-7 are 415, 8-9 the A72 at 1024, FACT dmesg-first-b13.txt). Only
#       ActivityManager puts processes there (OomAdjuster: SCHED_GROUP_
#       BACKGROUND / _RESTRICTED); no platform or vendor rc does.
#   everything else -> the present mask, as before. system-background must
#       stay wide: A13 SurfaceFlinger moves its own threads, main thread
#       included, into system-background (main_surfaceflinger.cpp:145,
#       SFMainPolicy / SFRenderEnginePolicy in task_profiles.json), and with
#       debug.renderengine.backend=gles every GPU composition runs on that
#       main thread -- narrowing it would push composition onto LITTLE cores.
LITTLE=0-3

sync_once() {
    # Prefer the present set (durable with the cpus_requested backport: the
    # kernel intersects it with the active mask itself). If the write is
    # rejected -- a kernel without the backport refuses offline cpus -- fall
    # back to the online mask, which is the old behaviour.
    present=$(cat /sys/devices/system/cpu/present 2>/dev/null)
    online=$(cat /sys/devices/system/cpu/online 2>/dev/null)
    [ -n "$present$online" ] || return 0

    for set in foreground background top-app system-background restricted \
               foreground/boost camera-daemon; do
        [ -d "/dev/cpuset/$set" ] || continue
        case "$set" in
            background|restricted) want=$LITTLE ;;
            foreground) want=${PP_FOREGROUND:-$present} ;;
            *) want=$present ;;
        esac
        if [ -n "$want" ] && echo "$want" > "/dev/cpuset/$set/cpus" 2>/dev/null; then
            continue
        fi
        [ -n "$online" ] && echo "$online" > "/dev/cpuset/$set/cpus" 2>/dev/null || true
    done
}

# Interval chosen from the measured decay above: cores were pruned within eight
# seconds, so a minute-long patrol would leave the sets narrow almost all the
# time. Five seconds is cheap - the loop is a read, a handful of small writes
# and a sleep - and keeps the sets wide for most of every interval.
# LMK tiers of init.m95.mem.rc (GSI: FLYME13_KERNEL_PLAN.md:679-684). lmkd rewrites
# the kernel params on every LMK_TARGET (lmkd.cpp:1431-1455), e.g. after a
# system_server restart, and the boot_completed trigger fires only once
# (M95_PERF_AUDIT_20260924.md P1-2).
LMK_MINFREE=18432,23040,27648,32256,102400,122880
LMK_PARAM=/sys/module/lowmemorykiller/parameters/minfree
lmk_once() {
    [ -w "$LMK_PARAM" ] || return 0
    [ "$(cat "$LMK_PARAM" 2>/dev/null)" = "$LMK_MINFREE" ] && return 0
    echo "$LMK_MINFREE" > "$LMK_PARAM" 2>/dev/null || true
}

while true; do
    if [ "$PERFPROFILE" = 1 ]; then
        pp_cores_once
        # Parked (experimental, screen off): one core, nothing to sync; poll
        # the backlight every second so the cores are back right after unlock.
        if [ "$PP_PARKED" = 1 ]; then
            sleep 1
            continue
        fi
        sync_once
        pp_once
    else
        sync_once
        thermal_once
    fi
    lmk_once
    sleep 5
done
