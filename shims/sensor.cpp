// SensorEventQueue::getFd() const for the N camera stack (libmtkcam_sysutils).
// libsensor_vendor (hardware/lineage/compat) wraps an opaque NDK
// ASensorEventQueue and has no descriptor of its own. The first version returned
// -1: the camera's sensor-listener thread (Mtkcam@SensorLi) handed it to its
// Looper unchecked and the provider died with SIGSEGV at 0x10 in
// Looper::pollInner (tombstone 2026-09-24 21:22). Return a valid descriptor that
// never becomes readable instead: the Looper accepts it, the listener simply
// receives no sensor events (gyro-assisted features stay off), nothing crashes.
#include <log/log.h>
#include <sys/eventfd.h>

extern "C" int _ZNK7android16SensorEventQueue5getFdEv(const void* /*self*/) {
    static const int fd = eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK);
    ALOGW("m95: SensorEventQueue::getFd() has no real descriptor on the compat libsensor, "
          "returning a silent eventfd (%d)", fd);
    return fd;
}
