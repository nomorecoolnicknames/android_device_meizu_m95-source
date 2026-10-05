#!/vendor/bin/sh

set -u

PERFPROFILE=$(/vendor/bin/getprop persist.vendor.m95.perfprofile 2>/dev/null)
if [ "$PERFPROFILE" = 1 ] && [ -r /vendor/bin/m95-perfprofile.sh ]; then
    . /vendor/bin/m95-perfprofile.sh
else
    PERFPROFILE=
fi

HPS=
if [ -z "$PERFPROFILE" ] && [ "$(/vendor/bin/getprop persist.vendor.m95.hps 2>/dev/null)" = 1 ]; then
    read -r _ver < /proc/version
    case "$_ver" in
        *3.18.22-eng-g3243163a*|*3.18.22-eng-gf3c39e3e*) HPS=1 ;;
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

LMK_MINFREE=18432,23040,27648,32256,102400,122880
LMK_PARAM=/sys/module/lowmemorykiller/parameters/minfree
lmk_once() {
    [ -w "$LMK_PARAM" ] || return 0
    [ "$(cat "$LMK_PARAM" 2>/dev/null)" = "$LMK_MINFREE" ] && return 0
    echo "$LMK_MINFREE" > "$LMK_PARAM" 2>/dev/null || true
}

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
