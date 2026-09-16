// libm95shim_sf — SurfaceComposerClient/SurfaceControl legacy stubs.
//
// R removed the N-era global-transaction Surface API (openGlobalTransaction,
// createSurface, setLayer/show/hide on SurfaceControl, getBuiltInDisplay...).
// Needed at dlopen time by libgui_ext (display path), libaal, libshowlogo,
// thermalindicator, libperfservice. None of these drive real transactions
// during bring-up; stubs return inert values. If the display path proves to
// call them for real, forward to R's Transaction API (phase: display).
// sp<>-returning entries use the m681 return-type-c-linkage technique:
// an sp is one pointer, null is ABI-correct.
#include <stdint.h>

namespace android {
class String8;
class Rect;
class IBinder;
template <typename T>
class sp;
class Surface;
}  // namespace android

namespace {
struct NullSp {
    void* p;
};
}  // namespace

extern "C" {

// SurfaceComposerClient::getBuiltInDisplay(int) -> display id; 0 = primary.
int32_t _ZN7android21SurfaceComposerClient17getBuiltInDisplayEi(void* /*self*/,
                                                                int /*id*/) {
    return 0;
}

// SurfaceComposerClient::openGlobalTransaction() -> void.
void _ZN7android21SurfaceComposerClient21openGlobalTransactionEv(void* /*self*/) {
}

// SurfaceComposerClient::closeGlobalTransaction(bool) -> void.
void _ZN7android21SurfaceComposerClient22closeGlobalTransactionEb(void* /*self*/,
                                                                  bool /*synchronous*/) {
}

// SurfaceComposerClient::createSurface(String8,w,h,format,flags) -> null sp<Surface>.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wreturn-type-c-linkage"
NullSp _ZN7android21SurfaceComposerClient13createSurfaceERKNS_7String8Ejjij(
        void* /*self*/, const android::String8& /*name*/, uint32_t /*w*/,
        uint32_t /*h*/, int32_t /*format*/, uint32_t /*flags*/) {
    NullSp r;
    r.p = 0;
    return r;
}
#pragma clang diagnostic pop

// SurfaceComposerClient::setDisplayProjection(sp<IBinder>,orient,layerStack,disp)
// -> NO_ERROR.
int _ZN7android21SurfaceComposerClient20setDisplayProjectionERKNS_2spINS_7IBinderEEEjRKNS_4RectES8_(
        void* /*self*/, const void* /*token*/, uint32_t /*orient*/,
        const android::Rect& /*layerStack*/, const android::Rect& /*display*/) {
    return 0;
}

// SurfaceControl methods -> NO_ERROR.
int _ZN7android14SurfaceControl8setLayerEj(void* /*self*/, uint32_t /*layer*/) {
    return 0;
}
int _ZN7android14SurfaceControl4showEv(void* /*self*/) { return 0; }
int _ZN7android14SurfaceControl4hideEv(void* /*self*/) { return 0; }
int _ZN7android14SurfaceControl5clearEv(void* /*self*/) { return 0; }
int _ZN7android14SurfaceControl7setSizeEjj(void* /*self*/, uint32_t /*w*/,
                                           uint32_t /*h*/) {
    return 0;
}

}  // extern "C"

// android::IDumpTunnel::asInterface(const sp<IBinder>&) -- MediaTek's N-era
// libgui extension (dump tunnel from the composer into SurfaceFlinger), gone
// from R libgui. libgui_ext.so imports it and hwcomposer.mt6797.so cannot load
// without it (logcat 2026-09-06: "cannot locate symbol ... referenced by
// /vendor/lib64/libgui_ext.so"). Returns a null sp<>.
//
// ABI note: android::sp<T> is 8 bytes but NOT trivially destructible, so on
// arm64 it is returned through the hidden sret pointer (x8), not in x0. The
// NullSp above is trivially copyable and therefore comes back in x0 -- wrong
// for any caller that really uses the value. SpRet below has a user-provided
// destructor, which puts it in the same "returned in memory" class as sp<T>.
// (The older NullSp entries stay as they are: they exist for dlopen-time
// resolution only.)
namespace {
struct SpRet {
    void* p;
    SpRet() : p(nullptr) {}
    ~SpRet() {}
};
}  // namespace

// clang's -Wreturn-type-c-linkage is exactly the point here: the C-named
// symbol must return a C++-ABI (memory-class) value.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wreturn-type-c-linkage"
extern "C" SpRet _ZN7android11IDumpTunnel11asInterfaceERKNS_2spINS_7IBinderEEE(void* /*binder*/) {
    return SpRet();
}
#pragma clang diagnostic pop
