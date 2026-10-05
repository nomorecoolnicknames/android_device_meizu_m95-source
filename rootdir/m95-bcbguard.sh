#!/vendor/bin/sh

P=/dev/block/platform/mtk-msdc.0/11230000.msdc0/by-name/para
log() { echo "m95-bcbguard: $*" > /dev/kmsg; }
command_field() { dd if=$P bs=13 count=1 2>/dev/null; }

case "$1" in
arm)
    # 32-byte field: the 13-byte command, then NUL padding over whatever the
    # last writer left there ("bootonce-bootloader" is 19 bytes). init's own
    # `write` cannot emit NUL, hence dd.
    echo -n boot-recovery | dd of=$P bs=13 count=1 conv=notrunc 2>/dev/null
    dd if=/dev/zero of=$P bs=1 seek=13 count=19 conv=notrunc 2>/dev/null
    sync
    if [ "$(command_field)" = boot-recovery ]; then log armed; else log "ARM FAILED"; fi
    ;;
clear)
    sleep "${2:-300}"
    if [ "$(command_field)" = boot-recovery ]; then
        dd if=/dev/zero of=$P bs=32 count=1 conv=notrunc 2>/dev/null
        sync
        if [ "$(command_field)" = boot-recovery ]; then log "CLEAR FAILED"; else log cleared; fi
    else
        log "not armed, left as is"
    fi
    ;;
*)
    log "usage: arm | clear [seconds]"
    ;;
esac
