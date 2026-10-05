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

// static sp<IBinder> SurfaceComposerClient::getBuiltInDisplay(int32_t id) --
// removed in Q. Returns a null sp<> through the sret slot. The earlier entry
// returned an int and took a phantom `self`, so it never wrote the slot:
// libperfservice.so getDisplayResolution() (0x8ecc) then decStrong()s the
// slot at 0x8f00-0x8f18 when it is non-null -- i.e. whatever the stack held.
extern "C" SpRet _ZN7android21SurfaceComposerClient17getBuiltInDisplayEi(int32_t /*id*/) {
    return SpRet();
}
#pragma clang diagnostic pop

// static status_t SurfaceComposerClient::getDisplayInfo(const sp<IBinder>&,
// DisplayInfo*) -- removed in S (A13 libgui has getStaticDisplayInfo /
// getActiveDisplayMode instead). Imported by libgui_ext.so and
// libperfservice.so; hwcomposer.mt6797.so cannot load without it (A13 link
// audit, designs/M95_LINK_AUDIT_20260924.md). Both callers ignore the status
// and read w/h straight out of the struct (libgui_ext GuiExtPool::alloc
// 0x17350 -> ldr [sp,#40]; libperfservice getDisplayResolution 0x8ed8 ->
// ldp [sp,#8]), so the struct must be filled. Asking SurfaceFlinger is not an
// option from a vendor process: vendor libgui talks to /dev/vndbinder, where
// SF is not registered, and ComposerService would wait for it forever.
// Values: what this handset's HWC reported to the framework (LOS 16,
// captures/m95-boot-20260807/m95-logcat-1821.txt:1815: 1080 x 1920,
// fps=60.360004, density 480, 480.0 x 480.0 dpi, appVsyncOff 1000000,
// presDeadline 16567262, FLAG_SECURE).
namespace {
// N/O/P layout (los16-ct07 frameworks/native/include/ui/DisplayInfo.h); the
// caller reserves exactly these 48 bytes (libperfservice: sp+8 .. sp+56).
struct M95DisplayInfoN {
    uint32_t w;
    uint32_t h;
    float xdpi;
    float ydpi;
    float fps;
    float density;
    uint8_t orientation;
    bool secure;
    int64_t appVsyncOffset;
    int64_t presentationDeadline;
};
static_assert(sizeof(M95DisplayInfoN) == 48, "N DisplayInfo is 48 bytes");
}  // namespace

extern "C" int32_t _ZN7android21SurfaceComposerClient14getDisplayInfoERKNS_2spINS_7IBinderEEEPNS_11DisplayInfoE(
        const void* /*display*/, M95DisplayInfoN* info) {
    if (info == nullptr) return -22;  // BAD_VALUE
    info->w = 1080;
    info->h = 1920;
    info->xdpi = 480.0f;
    info->ydpi = 480.0f;
    info->fps = 60.36f;
    info->density = 3.0f;
    info->orientation = 0;
    info->secure = true;
    info->appVsyncOffset = 1000000;
    info->presentationDeadline = 16567262;
    return 0;  // NO_ERROR
}
