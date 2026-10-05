#!/system/bin/sh
# Publish the factory Bluetooth address from MTK NVRAM as a system property.
#
# WHY THIS IS NEEDED
#
# Pie's Bluetooth HAL gets the local address from BluetoothAddress::
# get_local_address(), which tries exactly three sources in order
# (hardware/interfaces/bluetooth/1.0/default/bluetooth_address.{h,cc}):
#
#   1. the file named by  ro.bt.bdaddr_path       - as ASCII "XX:XX:..."
#   2. the property       ro.boot.btmacaddr
#   3. the property       persist.service.bdroid.bdaddr
#
# and if all three fail its caller does LOG_ALWAYS_FATAL("No Bluetooth
# Address!"). On this device all three are unset, and stock's build.prop does
# not set them either - the Flyme stack read NVRAM directly, so it never needed
# them.
#
# The address itself is present and correct: /data/nvram/APCFG/APRDEB/BT_Addr
# is the MTK ap_nvram_btradio_struct record, whose first member is addr[6], and
# on this unit those six bytes read 90 f0 52 41 35 d6 - first octet 0x90 has
# neither the multicast nor the locally-administered bit set, so it is a
# genuine factory OUI address in natural byte order, not a reversed or
# generated one.
#
# So the only thing missing is publishing it. Reading NVRAM and setting
# persist.service.bdroid.bdaddr is the least invasive of the three routes: it
# needs no new file in a fixed format and no change to the HAL.
#
# Ordering: the HAL reads the address when Bluetooth is enabled, not at boot,
# so running at post-fs-data is early enough. /data must be mounted, which is
# what post-fs-data guarantees.

set -u

NV=/data/nvram/APCFG/APRDEB/BT_Addr

[ -r "$NV" ] || exit 0

# Already published (persist properties survive reboots) - leave it alone so a
# user-set or framework-set address is not overwritten on every boot.
case "$(getprop persist.service.bdroid.bdaddr)" in
    ??:??:??:??:??:??) exit 0 ;;
esac

addr=$(od -An -tx1 -N6 "$NV" 2>/dev/null | tr -d ' \n' | tr 'a-f' 'A-F')

# Six bytes, twelve hex digits, and not one of the two degenerate addresses
# NVRAM shows when it has never been provisioned.
case "$addr" in
    ????????????) ;;
    *) exit 0 ;;
esac
[ "$addr" = "000000000000" ] && exit 0
[ "$addr" = "FFFFFFFFFFFF" ] && exit 0

formatted=$(echo "$addr" | sed 's/../&:/g; s/:$//')
setprop persist.service.bdroid.bdaddr "$formatted"

exit 0
