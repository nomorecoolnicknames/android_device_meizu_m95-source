#!/vendor/bin/sh
# m95_cpuset patrol (init.m95.cpuset.rc): CPU placement, thermal trip table and
# LMK tiers for the deca-core MT6797. Runs as `/vendor/bin/sh <this file>` in
# its own domain (sepolicy/vendor/m95_scripts.te), loops every five seconds.
#
# Duties, each marked with its status (register: WORKAROUNDS.md in this tree):
#
#  1. hps hotplug off, all ten cores online once at start.       [TEMPORARY]
#     Unless persist.vendor.m95.hps=1 (vendor.prop default since build 38)
#     and the kernel is one of the hotplug-fixed ones: then hps stays on.

#     biggest idle-power cost on this port: with ten cores online deep idle
#     and SODI can never be entered (spm_v2/mt_idle.c:600-603).
#  2. cpuset masks: background/restricted -> LITTLE (0-3), the rest -> the
#     present mask, re-asserted every pass.                           [POLICY]
#     The masks are the device's job on A13 (init.rc:333-335). The loop exists
#     because 3.18 cgroup v1 dropped hotplugged cores from every set for good
#     (measured: all sets down to cpu4 within a minute, load average 20). The

#     cpusets restore on hotplug": the kernel keeps the mask that was written
#     and re-derives cpus_allowed on hotplug), so the loop is belt and braces
#     now. The root cpuset is read-only here (update_cpumask: -EACCES for
#     top_cpuset) and is not written.
#  3. mtktscpu trip table 85/80 C instead of the vendor policy's 58/57 C,
#     re-asserted every pass.                               [DEVIATION, kept]
#  4. LMK minfree tiers of init.m95.mem.rc, re-asserted after lmkd rewrites
#     them.                                                 [DEVIATION, kept]
#  5. A72 (cpu8-9) back online after suspend while the screen is on. [FOLLOWS 1]
#     Needed only while hps is off: hps_suspend() takes them down and nothing
#     else brings them back.
# With persist.vendor.m95.perfprofile=1, rootdir/m95-perfprofile.sh replaces 3
# and 5 with its own versions and narrows foreground.

set -u

# Performance / thermal profile, off unless persist.vendor.m95.perfprofile=1

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

# stop_machine race of reason 1 never gets an event to race on), but all ten
# cores are brought online once and left alone. Measured on the device:
# 10 min with 0-9 online, load ~13 -> steady, mtktscpu 63 C, thermald +
# thermalloadalgod running, WDT kicks every 5 s (the kicker was also fixed to
# survive hotplug, drivers/watchdog/mediatek/wdk). UI on 4 LITTLE cores was
# visibly sluggish; with A72 at 2.3 GHz it is not.
#

# (dynamic hotplug, so deep idle/SODI can be entered: mt_idle.c needs a single
# online CPU). Honoured only on kernels that carry the stop_machine hotplug
# repairs 9866c51b + 56c36fdf (reason 1 above) -- recognised by the uname
# suffix of the boots built for it, see meizu-fleet
# designs/MX6_A13_COMPONENT_COVERAGE_20261005.md. Any other kernel keeps hps
# off whatever the property says. Not with the perf profile, which manages the
# cores itself. Rollback: setprop persist.vendor.m95.hps 0 and reboot.

# uname gate below still decides.
HPS=
if [ -z "$PERFPROFILE" ] && [ "$(/vendor/bin/getprop persist.vendor.m95.hps 2>/dev/null)" = 1 ]; then
    read -r _ver < /proc/version
    case "$_ver" in
        *3.18.22-eng-g1c4ce619*|*3.18.22-eng-g3243163a*|*3.18.22-eng-gf3c39e3e*) HPS=1 ;;
    esac
fi
if [ "$HPS" = 1 ]; then
    echo 1 > /proc/hps/enabled 2>/dev/null || true
else
    echo 0 > /proc/hps/enabled 2>/dev/null || true
    for _cpu in ${PP_BOOT_CPUS:-1 2 3 4 5 6 7 8 9}; do
        echo 1 > "/sys/devices/system/cpu/cpu$_cpu/online" 2>/dev/null || true
    done
fi


# thermal daemon programs mtktscpu trips with cpu_adaptive_0/1 at 58/57 C, and in
# mtk_ts_cpu.c the trip bound to cpu_adaptive_N *is* the ATM target Tj -> the SoC
# is power-capped from 58 C, i.e. always (idle Tj ~60 C): little cluster cut to
# 1222 MHz, mid to 1625, games throttle right at launch.  MTK stock targets are
# ~85 C; the 110 C sysrst trip stays.  The daemon may rewrite the table on scene
# changes, so it is re-asserted from the patrol loop below.
TZCPU=/proc/driver/thermal/tzcpu
thermal_once() {
    [ -w "$TZCPU" ] || return 0
    # Shell builtins only: /system/bin/grep comes first in init's PATH, and a
    # vendor domain may not exec it under enforcing (m95_scripts.te) -- the
    # check would fail and the table would be rewritten on every pass.
    while IFS= read -r _l; do
        case "$_l" in *"trip_1=85000 0 cpu_adaptive_0"*) return 0 ;; esac
    done < "$TZCPU"
    echo "10 110000 0 mtktscpu-sysrst 85000 0 cpu_adaptive_0 80000 0 cpu_adaptive_1 65000 0 no-cooler 63000 0 no-cooler 60000 0 no-cooler 55000 0 no-cooler 50000 0 no-cooler 45000 0 no-cooler 40000 0 no-cooler 40" > "$TZCPU" 2>/dev/null || true
}


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

# [duty 4] LMK tiers of init.m95.mem.rc (GSI: FLYME13_KERNEL_PLAN.md:679-684). lmkd rewrites
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


# spm_script) the kernel suspends for the first time on this port, and
# hps_suspend() takes cpu8-9 down on every suspend without bringing them back
# (mt_hotplug_strategy_main.c:430-454). Measured on b24 with an RTC wake:
# online 0-9 before, 0-7 after one suspend. The perf profile restores them in
# pp_cores_once; this does the same on the default path: back online whenever
# the screen is on, left down while it is dark. The backlight reads 0 until
# the lights HAL first writes it, which only skips a pass -- the cores are
# online from the start of this script anyway.
big_back_once() {
    _b=1
    read -r _b < /sys/class/leds/lcd-backlight/brightness 2>/dev/null
    [ "$_b" = 0 ] && return 0
    for _c in 8 9; do
        _o=
        read -r _o < "/sys/devices/system/cpu/cpu$_c/online" 2>/dev/null
        [ "$_o" = 0 ] && echo 1 > "/sys/devices/system/cpu/cpu$_c/online" 2>/dev/null
    done
    return 0
}

# Five seconds: before the kernel fix cores were pruned from a freshly written
# set within eight seconds, so a minute-long patrol would have left the sets
# narrow almost all the time. A pass is a few reads, a few small writes and a
# sleep.
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
        # With hps on it owns the cores, A72 after suspend included.
        [ "$HPS" = 1 ] || big_back_once
        sync_once
        thermal_once
    fi
    lmk_once
    sleep 5
done
