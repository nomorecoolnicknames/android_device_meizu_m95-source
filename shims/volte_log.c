// libm95volte_logfilter — keeps SIP traffic of the VoLTE daemons out of logcat.
//
// volte_stack, volte_ua and volte_imcb (N blobs, 32-bit) print whole SIP
// messages at INFO under tags "VoLTE REG", "VoLTE SIPTX", "VoLTE SMS", "VoLTE

// capture m95-b23-volte-mts-20260926: 94 of 1840 INFO lines of VoLTE* tags
// match identifier patterns, 0 of 103 ERROR and 0 of 5 DEBUG lines. The tags
// contain a space, so no log.tag.* property can name them

//
// The three import only __android_log_print (+ __android_log_assert in
// volte_imcb), FACT llvm-readelf --dyn-syms. The linker puts a
// TARGET_LD_SHIM_LIBS library after LD_PRELOAD and before the executable's
// DT_NEEDED (bionic/linker/linker_main.cpp:480-487), so this definition wins
// over liblog's in those processes. Lines of VoLTE* tags below WARN are
// dropped with liblog's own "not loggable" answer; everything else goes to
// liblog unchanged.
//
// Built and wired only with M95_VOLTE_LOGFILTER=true (BoardConfig.mk,
// device.mk): off until VoLTE registration and a call are checked on the


#include <android/log.h>
#include <errno.h>
#include <stdarg.h>
#include <string.h>

__attribute__((visibility("default")))
int __android_log_print(int prio, const char* tag, const char* fmt, ...) {
    if (prio < ANDROID_LOG_WARN && tag != NULL && strncmp(tag, "VoLTE", 5) == 0)
        return -EPERM;

    va_list ap;
    va_start(ap, fmt);
    int ret = __android_log_vprint(prio, tag, fmt, ap);
    va_end(ap);
    return ret;
}
