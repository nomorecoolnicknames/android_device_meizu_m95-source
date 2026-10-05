#!/vendor/bin/sh

TOP=/data/vendor/m95-powertrap
IV=${1:-1}
B=/sys/class/power_supply

mkdir -p "$TOP" || exit 1
D=$TOP/$(date +%Y%m%d-%H%M%S)
mkdir -p "$D" || exit 1

# Keep the newest four runs.
_n=0
for _d in $(ls -1r "$TOP"); do
    _n=$((_n + 1))
    [ "$_n" -gt 4 ] && rm -rf "${TOP:?}/$_d"
done

{
    echo "start $(date '+%F %T') iv=$IV"
    echo "bootreason $(getprop ro.boot.bootreason) last=$(getprop sys.boot.reason.last)"
    cat /proc/cmdline
} > "$D/info.txt" 2>&1

# Power/Home press lines ("kpd: Power Key generate", "PMIC reset Key
# generate") are what the shutdown hunt needs (m95-diag s.10). The kernel's kpd
# privacy fix keeps them off unless kpd_show_hw_keycode is set; this is a debug
# tool, so it turns them on for the rest of this boot. (On #145 the switch
# already defaults to 1.)
echo 1 > /sys/module/kpd/parameters/kpd_show_hw_keycode 2>/dev/null

# Kernel lines of interest, flushed per line.
dmesg -w 2>/dev/null | while IFS= read -r _l; do
    case "$_l" in
        *"kpd:"*|*"Cable in"*|*"Cable out"*|*"CHR_Type"*|*"PM: suspend"*|\
        *"reboot:"*|*"Power down"*|*"shutdown"*|*"chg0_irq"*|*"UVLO"*|\
        *"init: Received sys.powerctl"*|*"init: Got shutdown"*)
            echo "$_l" >> "$D/kmsg.txt"
            if [ -f "$D/kmsg.txt" ] && [ "$(stat -c %s "$D/kmsg.txt")" -gt 2097152 ]; then
                mv "$D/kmsg.txt" "$D/kmsg.1.txt"
            fi
            ;;
    esac
done &

echo "t,up,cap,uV,uA,temp,status,usb,ac,tj,bl,online,cpu8" > "$D/p.csv"
_i=0
while true; do
    echo "$(date +%T),$(cut -d' ' -f1 /proc/uptime),$(cat $B/battery/capacity),$(cat $B/battery/voltage_now),$(cat $B/battery/current_now),$(cat $B/battery/temp),$(cat $B/battery/status),$(cat $B/usb/online),$(cat $B/ac/online),$(cat /sys/class/thermal/thermal_zone1/temp),$(cat /sys/class/leds/lcd-backlight/brightness),$(cat /sys/devices/system/cpu/online),$(cat /sys/devices/system/cpu/cpu8/cpufreq/scaling_cur_freq 2>/dev/null)" >> "$D/p.csv" 2>/dev/null
    _i=$((_i + 1))
    if [ $((_i % 600)) = 0 ] && [ "$(stat -c %s "$D/p.csv")" -gt 4194304 ]; then
        mv "$D/p.csv" "$D/p.1.csv"
    fi
    sync
    sleep "$IV"
done
