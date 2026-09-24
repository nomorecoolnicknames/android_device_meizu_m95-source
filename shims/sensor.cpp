// SensorEventQueue::getFd() const for the N camera stack (libmtkcam_sysutils).
// libsensor_vendor (hardware/lineage/compat) wraps an opaque NDK
// ASensorEventQueue and has no descriptor to give, so this reports "no fd"
// and the caller's sensor listener stays idle; without the symbol
// camera.mt6797.so does not load at all (2026-09-24).
#include <log/log.h>

extern "C" int _ZNK7android16SensorEventQueue5getFdEv(const void* /*self*/) {
    ALOGW("m95: SensorEventQueue::getFd() is not available on the compat libsensor, returning -1");
    return -1;
}
