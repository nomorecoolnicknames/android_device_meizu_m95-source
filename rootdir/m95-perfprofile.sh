# Performance / thermal profile for the MX6 (m95, MT6797 Helio X20).
#
# Sourced by m95-cpuset.sh, and only when persist.vendor.m95.perfprofile=1.
# The property is read once, at service start: set it and reboot. With the
# property unset the device behaves exactly as it did before this file existed.
# Every value, the source line it rests on and the marker that shows it took
# effect: meizu-fleet/designs/M95_PERF_PROFILE_20260925.md. Kernel paths below
# are relative to meizu_mx6_m95/kernel/m685.
#
# WHAT IT IS FOR (capture meizu-fleet/captures/m95-perf-game-20260924.log):
# in a 3D game mtktscpu went 64 -> 91-99 C in 15 s, the GPU was cut to its
# lowest OPP (g_limited_max_id=6, 238 MHz) and the A72 pair stayed at
# 2314 MHz. Three mechanisms, read in source:
#
#  1. The vendor policy thermal.conf gives ATM floors of 560 mW CPU and 360 mW
#     GPU (clatm_setting id 0; the capture's "limited power = 560" is that
#     floor). 360 mW buys only GPU OPP 6.
#  2. PPM spends the CPU budget without the A72. It plans to switch cores off
#     when the budget is small; with hps off (m95-cpuset.sh) nothing switches
#     them off, and a cluster PPM believes empty gets no frequency cap at all
#     (ppm_v1/src/mt_ppm_main.c:144-147, 362-366; the power state is also
#     dropped to LL_ONLY by budget, mt_ppm_main.c:845-849). INFERENCE: that is
#     why the A72 ran uncapped while the A53s and the GPU starved.
#  3. The interactive governor ignores hispeed_freq for the A53-L and A72
#     clusters in the default power mode and sends them straight to their top
#     OPP on any load over go_hispeed_load (drivers/cpufreq/
#     cpufreq_interactive.c:399-402) -- the least efficient point of the A72:
#     1512 mW per core at 2314 MHz against 966 at 1781 (ppm_v1 power table).

# Sub-switches, read once like the main one.
#   persist.vendor.m95.perfprofile.big  = 0: keep the A72 pair (cpu8-9)
#       offline for good. Default: bring them back when the screen is on.
#   persist.vendor.m95.perfprofile.park = 1: EXPERIMENTAL, see pp_cores_once.
PP_BIG=$(/vendor/bin/getprop persist.vendor.m95.perfprofile.big 2>/dev/null)
PP_PARK=$(/vendor/bin/getprop persist.vendor.m95.perfprofile.park 2>/dev/null)

# Cores m95-cpuset.sh brings online at start (it used to be all nine).
if [ "$PP_BIG" = 0 ]; then
    PP_BOOT_CPUS="1 2 3 4 5 6 7"
else
    PP_BOOT_CPUS="1 2 3 4 5 6 7 8 9"
fi

# CPUSET. foreground loses the A72: they stay with top-app (the app in front,
# and SystemUI while it shows the shade or keyguard) and with system-background,
# where SurfaceFlinger composites (see LITTLE in m95-cpuset.sh). Foreground
# services and visible-but-not-top apps get the 8 A53s.
PP_FOREGROUND=0-7

# Readbacks use shell builtins only. m95_cpuset is a vendor domain: under
# enforcing it may not exec /system/bin grep/sed, which come first in init's
# PATH -- a failed check would rewrite its knob on every pass.
# pp_has <file> <case-pattern>: some line of <file> matches the pattern
pp_has() {
    [ -r "$1" ] || return 1
    while IFS= read -r _l; do
        case "$_l" in $2) return 0 ;; esac
    done < "$1"
    return 1
}

# write $2 to $1 unless $1 already reads back as $2
pp_set() {
    [ -w "$1" ] || return 0
    _v=
    read -r _v < "$1" 2>/dev/null
    [ "$_v" = "$2" ] || echo "$2" > "$1" 2>/dev/null
}

# THERMAL
TD=/proc/driver/thermal
# Mode 0 of MTK's continuous TM: the ATM target is the cpu_adaptive_0 trip
# itself. thermal.conf sets mode 2, where the target is whatever
# thermalloadalgod sends over netlink (coolers/mtk_cooler_atm.c:1016-1028).
# This is Meizu's own mode-0 line, from thermal.off.conf.
PP_CTM="0 85000 67000 45000 48000 75000 61000 355000 6000 285016 4667 25 25 10000"
# ATM cooler 0: GPU floor 1000 mW, CPU floor PP_MIN_CPU, ceilings = platform
# max (fields: id first_step theta_rise theta_fall min_change min_cpu max_cpu
# min_gpu max_gpu; mtk_cooler_atm.c:1176-1270).
#  - GPU: 1000 mW keeps 442 MHz up to ~80 C and 365 MHz above, instead of
#    238 (mt_gpufreq power table plus leakage; INFERENCE).
#  - CPU: PPM's thermal walk (mt_ppm_main.c:290-344; efficiency and delta
#    tables in mach/mt6797/mt_ppm_efficiency_table.h) cuts the A72 first and,
#    counted from all cores at top OPP, plans to switch an A72 core off once it
#    has taken 5496 of its power units -- a plan hps-off never carries out
#    (mechanism 2). The start is the chip-calibrated "max power" (TT table
#    6438, a leaky FF part ~7500; mt_ppm_policy_thermal.c:83-97), so the floor
#    is derived from it here: max - 5200, never below 1300.
PP_MIN_CPU=1300
_mx=
if [ -r /proc/ppm/policy/thermal_cur_power ]; then
    while IFS= read -r _l; do
        case "$_l" in "max power = "*) _mx=${_l#max power = } ;; esac
    done < /proc/ppm/policy/thermal_cur_power
fi
case "$_mx" in
    ''|*[!0-9]*) ;;
    *) [ $((_mx - 5200)) -gt $PP_MIN_CPU ] && PP_MIN_CPU=$((_mx - 5200)) ;;
esac
PP_ATM0="0 3000 10 15 1 $PP_MIN_CPU 0 1000 0"
# Trip table: ATM holds 80 C. Before that, two static CPU-only power caps
# (DTM cooler cpuNN = 700 + 100*NN mW, coolers/mtk_cooler_dtm.c:120-170):
# 4.0 W from 72 C, 3.4 W from 76 C, both above PP_MIN_CPU for either chip
# corner; the GPU is not touched. PPM takes each cut from the least efficient
# cluster, which is the A72 once PPM counts it (PPM below). sysrst stays at
# 110 C. Format: 10 triplets "temp type cooler" + polling ms
# (thermal_zones/mtk_ts_cpu.c:1119-1133).
PP_TZCPU="4 110000 0 mtktscpu-sysrst 80000 0 cpu_adaptive_0 76000 0 cpu27 72000 0 cpu33 0 0 no-cooler 0 0 no-cooler 0 0 no-cooler 0 0 no-cooler 0 0 no-cooler 0 0 no-cooler 40"
PP_DTM="cpu27 cpu33"

pp_thermal_once() {
    [ -w "$TD/tzcpu" ] || return 0
    # thermal_manager (oneshot, class main) loads thermal.conf after this
    # service has started, hence a patrol and not a single write.
    pp_has "$TD/clctm" 'ctm 0' || echo "$PP_CTM" > "$TD/clctm" 2>/dev/null
    pp_atm0_ok || echo "$PP_ATM0" > "$TD/clatm_setting" 2>/dev/null
    # Rewritten only when it differs: every tzcpu write unregisters the zone,
    # resets ATM and caps the CPU at 900 mW meanwhile (mtk_ts_cpu.c:1141-1145,
    # 1276-1280).
    if ! pp_has "$TD/tzcpu" 'trip_1=80000 0 cpu_adaptive_0' ||
       ! pp_has "$TD/tzcpu" 'trip_3=72000 0 cpu33'; then
        echo "$PP_TZCPU" > "$TD/tzcpu" 2>/dev/null
    fi
    # 2 C hysteresis on the static caps; without it they flap at the trip
    # (mtk_thermal_monitor.c:1095-1105, 1192-1193).
    for _c in $PP_DTM; do
        pp_has "/proc/mtkcooler/$_c" 'EXIT val=* threshold=2000 *' ||
            echo "EXIT 2000" > "/proc/mtkcooler/$_c" 2>/dev/null
    done
}

# Cooler 0 block of clatm_setting (mtk_cooler_atm.c:1145-1153) carries both
# floors; the other two coolers print the same labels.
pp_atm0_ok() {
    [ -r "$TD/clatm_setting" ] || return 1
    _in=0; _okc=0; _okg=0
    while IFS= read -r _l; do
        case "$_l" in
            cpu_adaptive_00) _in=1 ;;
            cpu_adaptive_*) _in=0 ;;
            " m cpu = $PP_MIN_CPU") [ $_in = 1 ] && _okc=1 ;;
            " m gpu = 1000") [ $_in = 1 ] && _okg=1 ;;
        esac
    done < "$TD/clatm_setting"
    [ $_okc = 1 ] && [ $_okg = 1 ]
}

# PPM. Pin the power state to 4LL_L: PPM then counts every cluster in its
# thermal arithmetic, and the budget can no longer push the state down to
# LL_ONLY, which drops the A72 from it (mechanism 2). A fixed state
# overrides both HICA and the budget (ppm_v1/src/mt_ppm_policy_hica.c:
# 221-222, 271-272). With hps off the state's core limits change nothing.
# The readback shows the pinned state, or HICA's own when nothing is pinned
# (hica.c:426-427), and HICA starts in 4LL_L -- so the first pass writes
# unconditionally; dmesg then has "fix_power_state = 4LL_L" (hica.c:458).
PP_HICA=/proc/ppm/policy/hica_power_state
PP_HICA_SET=0
pp_ppm_once() {
    [ -w "$PP_HICA" ] || return 0
    if [ "$PP_HICA_SET" = 0 ] || ! pp_has "$PP_HICA" 'hica_state = 2 (*'; then
        echo 2 > "$PP_HICA" 2>/dev/null && PP_HICA_SET=1
    fi
}

# GOVERNOR. cpufreq_power_mode 2 ("just make") is the mode in which the
# interactive governor honours hispeed_freq and min_sample_time on every
# cluster; its only consumer is that governor (mt_cpufreq.c:5782-5799). With
# init.m95.mem.rc's hispeed_freq 1391000 the first step becomes LL 1391,
# L 1417, A72 1495 MHz instead of L 1846 and A72 2314.
# target_loads / above_hispeed_delay are global (one policy per cluster but
# no per-policy tunables), so they are keyed by frequency: above 2 GHz only
# the A72 exist, and they go there only at ~99 % load, after 60 ms at 1781+.
IA=/sys/devices/system/cpu/cpufreq/interactive
PP_TARGET_LOADS="85 1391000:90 1781000:95 2000000:99"
PP_ABOVE_HISPEED="20000 1781000:60000"
pp_gov_once() {
    pp_has /proc/cpufreq/cpufreq_power_mode 'Just_Make_Mode' ||
        echo 2 > /proc/cpufreq/cpufreq_power_mode 2>/dev/null
    pp_set "$IA/target_loads" "$PP_TARGET_LOADS"
    pp_set "$IA/above_hispeed_delay" "$PP_ABOVE_HISPEED"
    # Touch boost floor for LL/L, 300 ms per touch (performance/perfmgr/
    # perfmgr_touch.c:65-92); kernel default 1066 MHz, Flyme's TouchBoost used
    # >=1391 on LL for 1 s.
    pp_set /proc/perfmgr/touch/tb_freq 1391000
}

pp_once() {
    pp_thermal_once
    pp_ppm_once
    pp_gov_once
}

# CORES. hps_suspend() offlines cpu8-9 on every suspend, even with hps off,
# and nothing brings them back (mt_hotplug_strategy_main.c:430-454;
# enable_nonboot_cpus only restores the cores it took down itself). Without
# this the A72 are gone after the first sleep on battery.
#
# park=1 (EXPERIMENTAL, default off): after two dark passes, offline every
# core but cpu0 until the screen comes back. On this SoC deep idle and SODI
# are entered only with a single core online (base/power/spm_v2/mt_idle.c:
# 600-603) and per-core idle (MCDI) is compiled out, so with ten cores online
# the SoC never idles deeply while awake. It also caps a background hog at
# one A53. Cost: nine cpu_down per screen-off, the operation behind the
# 2026-09-06 hps panic (m95-cpuset.sh) -- soak test before trusting it.
BL=/sys/class/leds/lcd-backlight/brightness
PP_DARK=0
PP_PARKED=0
# The backlight reads 0 from boot until the lights HAL first writes it
# (leds_drv.c has no brightness_get), so darkness only counts once the screen
# has been seen on.
PP_SEEN_ON=0

pp_screen_on() {
    _b=1
    read -r _b < "$BL" 2>/dev/null
    [ "$_b" != 0 ]
}

# pp_cpu <n> <0|1>: set cpu<n> online state unless it is already there
pp_cpu() {
    _o=
    read -r _o < "/sys/devices/system/cpu/cpu$1/online" 2>/dev/null
    [ -n "$_o" ] && [ "$_o" != "$2" ] &&
        echo "$2" > "/sys/devices/system/cpu/cpu$1/online" 2>/dev/null
    return 0
}

pp_cores_once() {
    if pp_screen_on; then
        PP_SEEN_ON=1
        PP_DARK=0
        # Every pass, not only on the transition: a cpu_up that failed (EBUSY
        # after an aborted suspend, kernel/cpu.c:194-205) is retried. A core
        # already online costs one builtin read.
        if [ "$PP_PARK" = 1 ]; then
            for _c in 1 2 3 4 5 6 7; do pp_cpu $_c 1; done
            PP_PARKED=0
        fi
        if [ "$PP_BIG" = 0 ]; then
            pp_cpu 9 0; pp_cpu 8 0
        else
            pp_cpu 8 1; pp_cpu 9 1
        fi
        return 0
    fi
    [ "$PP_SEEN_ON" = 1 ] || return 0
    PP_DARK=$((PP_DARK + 1))
    if [ "$PP_BIG" = 0 ]; then
        pp_cpu 9 0; pp_cpu 8 0
    fi
    if [ "$PP_PARK" = 1 ] && [ "$PP_DARK" -ge 2 ]; then
        for _c in 9 8 7 6 5 4 3 2 1; do pp_cpu $_c 0; done
        PP_PARKED=1
    fi
    return 0
}
