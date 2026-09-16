// libm95shim_ui — N-to-R libui forwarders + Fence ctor/dtor.
//
// Missing in R (verified by nm on the built R libui.so):
//   GraphicBuffer::lock(uint32_t,void**)                       N: lockEjPPv
//     R: lockEjPPvPiS3_ (extra out-params, forwarded as null)
//   GraphicBufferMapper::lock(handle,usage,rect,vaddr)          N: 5 args
//     R: ...PPvPiS9_ (7 args, extras nulled)
//   Fence C1/C2/D1/D2 — R inlined them (unique_fd, header-only), no exports.
//     Layout identical in both ABIs (LightRefBase mCount@0, fd@4 — verified
//     against R frameworks/native/libs/ui/include/ui/Fence.h), so the m681
//     Pie-era bodies port verbatim.
// VNDK note: manual declarations only, no libui linkage (cf. shims/gui.cpp).
#include <stddef.h>
#include <stdint.h>
#include <unistd.h>

namespace android {
class Rect;
class GraphicBuffer;
class GraphicBufferMapper;
struct native_handle;
}  // namespace android

extern "C" {

// ---- R-side targets (system libui, resolved at runtime under lite) ----
int _ZN7android13GraphicBuffer4lockEjPPvPiS3_(
        android::GraphicBuffer*, uint32_t, void**, int32_t*, int32_t*);
int _ZN7android19GraphicBufferMapper4lockEPK13native_handlejRKNS_4RectEPPvPiS9_(
        android::GraphicBufferMapper*, const android::native_handle*,
        uint32_t, const android::Rect&, void**, int32_t*, int32_t*);
int _ZN7android13GraphicBuffer9lockAsyncEjPPviPiS3_(
        android::GraphicBuffer*, uint32_t, void**, int, int32_t*, int32_t*);

// ---- N-ABI entries ----
int _ZN7android13GraphicBuffer4lockEjPPv(
        android::GraphicBuffer* self, uint32_t inUsage, void** vaddr) {
    return _ZN7android13GraphicBuffer4lockEjPPvPiS3_(
            self, inUsage, vaddr, NULL, NULL);
}

int _ZN7android13GraphicBuffer9lockAsyncEjPPvi(
        android::GraphicBuffer* self, uint32_t inUsage, void** vaddr,
        int fenceFd) {
    return _ZN7android13GraphicBuffer9lockAsyncEjPPviPiS3_(
            self, inUsage, vaddr, fenceFd, NULL, NULL);
}

int _ZN7android19GraphicBufferMapper4lockEPK13native_handlejRKNS_4RectEPPv(
        android::GraphicBufferMapper* self, const android::native_handle* handle,
        uint32_t inUsage, const android::Rect& bounds, void** vaddr) {
    return _ZN7android19GraphicBufferMapper4lockEPK13native_handlejRKNS_4RectEPPvPiS9_(
            self, handle, inUsage, bounds, vaddr, NULL, NULL);
}

// ---- Fence (m681-proven bodies; R layout identical) ----
struct M95Fence {
    int32_t mCount;
    int mFenceFd;
};

void _ZN7android5FenceC2Ev(M95Fence* self) {
    if (self) {
        self->mCount = 0;
        self->mFenceFd = -1;
    }
}
void _ZN7android5FenceC1Ev(M95Fence* self) { _ZN7android5FenceC2Ev(self); }
void _ZN7android5FenceC2Ei(M95Fence* self, int fenceFd) {
    if (self) {
        self->mCount = 0;
        self->mFenceFd = fenceFd;
    }
}
void _ZN7android5FenceC1Ei(M95Fence* self, int fenceFd) {
    _ZN7android5FenceC2Ei(self, fenceFd);
}
void _ZN7android5FenceD2Ev(M95Fence* self) {
    if (self && self->mFenceFd != -1) close(self->mFenceFd);
}
void _ZN7android5FenceD1Ev(M95Fence* self) { _ZN7android5FenceD2Ev(self); }

}  // extern "C"
