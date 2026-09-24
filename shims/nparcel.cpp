// libm95shim_nparcel — "box" ABI adapter for the Nougat android::Parcel that
// the stock MTK libril (shipped renamed as /vendor/lib64/librilimp.so) keeps
// as a *by-value* stack/heap local.
//
// THE BUG (FACT, capture m95-b16-rild-crash-20260924)
// ---------------------------------------------------
// librilimp was compiled against Nougat, where sizeof(android::Parcel) on LP64
// is 104 bytes. On Android 13 it is 120 (Parcel grew mVariantFields et al., and
// initState() now writes a 64-bit zero at object offset 112). Every proxy path
// in librilimp reserves exactly 104 bytes for a Parcel — 9 functions build one
// on the stack (add x0,sp,#N ; Parcel::Parcel()), 3 more build one on the heap
// with operator new(104). Against the A13 libbinder the constructor writes 16
// bytes past that storage; the tail slot of the box (offset 112) lands on the
// caller's saved x22 / an adjacent heap object. On teardown ~Parcel() then does
// RefBase::decStrong() through the clobbered word:
//   #00 libutils RefBase::decStrong+16  (x0=0x139)
//   #01 librilimp IMS_RIL_onUnsolicitedResponseSocket+1032  (~Parcel at 0x202dc)
// => SIGSEGV every ~5 s once ForgeImsService connects to IMS_RIL_SOCKET_1.
//
// THE FIX (a box, not a frame-widen)
// ----------------------------------
// tools/librilimp-box-nparcel.py renames the 19 imported android::Parcel method
// strings in librilimp's .dynstr to android::Pbrcel (same length, 6Parcel ->
// 6Pbrcel) and adds this library to its DT_NEEDED. librilimp now calls
// android::Pbrcel::*; those symbols resolve here, NOT to the real libbinder.
// This library treats librilimp's 104-byte box as opaque storage whose FIRST
// 8 bytes hold a pointer to a heap-allocated *real* android::Parcel, and proxies
// every one of the 19 methods to it. The box never overflows (only 8 of its 104
// bytes are used) and the real 120-byte Parcel lives on our heap where its full
// layout fits.
//
// WHY THIS IS SAFE (INFERENCE from disassembly, tools/scan of librilimp)
// ----------------------------------------------------------------------
//  * librilimp reads Parcel state ONLY through these 19 out-of-line methods —
//    no inline access to N-layout header fields (verified: every [reg,#off]
//    through a Parcel `this` register is a false hit on a reused stack slot or
//    an unrelated global; no memcpy/memset of a live box).
//  * No Parcel object crosses the librilimp <-> librilmtk/libbinder boundary.
//    The IMS entries (IMS_RIL_onRequestComplete / IMS_RIL_onUnsolicitedResponse
//    / IMS_isRilRequestFromIms / IMS_RILA_register) and enqueue() take raw
//    (void*, size_t) buffers; the only Parcel-typed export is
//    nullParcelReleaseFunction (raw bytes). appendFrom()'s `other` is itself a
//    librilimp box, so both sides unbox to real Parcels here.
//  * String16 is a single char16_t* on both N and A13 (8 bytes), so the
//    by-value readString16()/writeString16(String16&) hand-off keeps working.
//
// See meizu-fleet/BRINGUP_STATE.md (m95, build #16 rild crash) for the full
// evidence chain and the next-capture verification commands.

#include <cstddef>
#include <cstdint>

#include <binder/Parcel.h>
#include <utils/Errors.h>
#include <utils/String16.h>

namespace android {

// The box the compiler operates on: exactly the pointer we stash in librilimp's
// storage. sizeof(Pbrcel) == 8, well within librilimp's 104-byte reservation;
// nothing but mReal is ever touched.
class Pbrcel {
public:
    Pbrcel();
    ~Pbrcel();

    status_t        appendFrom(const Pbrcel* parcel, size_t start, size_t len);
    status_t        writeInt32(int32_t val);
    status_t        writeInt64(int64_t val);
    status_t        writeString16(const char16_t* str, size_t len);
    status_t        writeString16(const String16& str);
    status_t        write(const void* data, size_t len);
    status_t        setData(const uint8_t* buffer, size_t len);

    const void*     readInplace(size_t len) const;
    size_t          dataPosition() const;
    String16        readString16() const;
    void            setDataPosition(size_t pos) const;
    const char16_t* readString16Inplace(size_t* outLen) const;
    const uint8_t*  data() const;
    status_t        read(void* outData, size_t len) const;
    size_t          dataSize() const;
    status_t        readInt32(int32_t* pArg) const;
    int32_t         readInt32() const;

private:
    Parcel* mReal;
};

// First word of librilimp's box <-> the heap Parcel it stands for.
static inline Parcel* real(const Pbrcel* self) {
    return *reinterpret_cast<Parcel* const*>(self);
}

Pbrcel::Pbrcel() {
    mReal = new Parcel();
}

Pbrcel::~Pbrcel() {
    delete real(this);
}

status_t Pbrcel::appendFrom(const Pbrcel* parcel, size_t start, size_t len) {
    return real(this)->appendFrom(real(parcel), start, len);
}

status_t Pbrcel::writeInt32(int32_t val) {
    return real(this)->writeInt32(val);
}

status_t Pbrcel::writeInt64(int64_t val) {
    return real(this)->writeInt64(val);
}

status_t Pbrcel::writeString16(const char16_t* str, size_t len) {
    return real(this)->writeString16(str, len);
}

status_t Pbrcel::writeString16(const String16& str) {
    return real(this)->writeString16(str);
}

status_t Pbrcel::write(const void* data, size_t len) {
    return real(this)->write(data, len);
}

status_t Pbrcel::setData(const uint8_t* buffer, size_t len) {
    return real(this)->setData(buffer, len);
}

const void* Pbrcel::readInplace(size_t len) const {
    return real(this)->readInplace(len);
}

size_t Pbrcel::dataPosition() const {
    return real(this)->dataPosition();
}

String16 Pbrcel::readString16() const {
    return real(this)->readString16();
}

void Pbrcel::setDataPosition(size_t pos) const {
    real(this)->setDataPosition(pos);
}

const char16_t* Pbrcel::readString16Inplace(size_t* outLen) const {
    return real(this)->readString16Inplace(outLen);
}

const uint8_t* Pbrcel::data() const {
    return real(this)->data();
}

status_t Pbrcel::read(void* outData, size_t len) const {
    return real(this)->read(outData, len);
}

size_t Pbrcel::dataSize() const {
    return real(this)->dataSize();
}

status_t Pbrcel::readInt32(int32_t* pArg) const {
    return real(this)->readInt32(pArg);
}

int32_t Pbrcel::readInt32() const {
    return real(this)->readInt32();
}

}  // namespace android
