/*
 * The part of MediaTek's NSCam::IMetadata that m95_scaler_raw.cpp touches,
 * declared from the blob itself rather than from a source header.
 *
 * LOS16 built this library against vendor/mediatek/mmsdk_feature, which this
 * tree does not have, and a header of the wrong MediaTek generation is worse
 * than none: in the metadata library this device ships, entryFor() returns a
 * reference, not an entry by value. FACT (objdump of
 * vendor/lib/libmtkcam_metadata.so, sha256 in the design note):
 * Implementor::entryFor takes (this, tag) and returns a pointer into its
 * KeyedVector, or to an empty default entry at this+24 when the tag is absent,
 * and AppStreamMgr::checkStream in libcam3_app calls vtable slot 9 with no
 * result buffer and uses r0 as the entry. A by-value declaration would make
 * clang pass a result buffer in r0 and `this` in r1 -- measured with this
 * tree's clang-r450784d -- and the blob would read its pimpl from our stack.
 *
 * Every class here is only ever reached through a pointer the vendor handed
 * over, so only the vtable slot order has to match. The order is the blob's own,
 * decoded from _ZTVN5NSCam9IMetadataE (15 slots) and
 * _ZTVN5NSCam9IMetadata6IEntryE (43 slots) through their R_ARM_ABS32
 * relocations. Slots this library never calls are placeholders with names that
 * say so; declaring them keeps every later slot at the right index.
 *
 * Nothing here is defined, and nothing is called by symbol. The destructors in
 * slots 0 and 1 are declared as ordinary virtuals on purpose: with a real
 * ~IEntry() in this header the compiler could emit a direct call to
 * _ZN5NSCam9IMetadata6IEntryD1Ev, an undefined symbol that bionic must bind
 * when it links this library as a shim of the provider executable -- before
 * libmtkcam_metadata exists in the process. A shim that cannot be linked is not
 * skipped: the provider does not start, and the device has no cameras. This
 * library never constructs or destroys an entry; it only edits the ones the
 * vendor built.
 *
 * 32-bit only: the camera provider on this device is the 32-bit
 * android.hardware.camera.provider@2.4-service (compile_multilib "32").
 */

#pragma once

#include <stdint.h>

namespace NSCam {

typedef uint8_t MUINT8;
typedef int32_t MINT32;
typedef uint32_t MUINT32;
typedef int64_t MINT64;
typedef float MFLOAT;
typedef unsigned int MUINT;
typedef int MBOOL;
typedef int MERROR;

// An empty tag type passed by value to select an overload; it carries nothing.
template <typename T>
struct Type2Type {
    typedef T type;
};

class IMetadata {
public:
    class IEntry {
    public:
        virtual void slot00_complete_object_destructor();
        virtual void slot01_deleting_destructor();
        virtual MUINT32 tag() const;                                  // 2
        virtual MINT32 type() const;                                  // 3
        virtual MBOOL isEmpty() const;                                // 4
        virtual MUINT count() const;                                  // 5
        virtual void slot06_capacity();
        virtual void slot07_setCapacity();
        virtual void slot08_clear();
        virtual void slot09_removeAt();
        virtual void push_back(MUINT8 const& item, Type2Type<MUINT8>);  // 10
        virtual void slot11_editItemAt_u8();
        virtual void slot12_itemAt_u8();
        virtual void push_back(MINT32 const& item, Type2Type<MINT32>);  // 13
        virtual void slot14_editItemAt_i32();
        virtual void slot15_itemAt_i32();
        virtual void push_back(MFLOAT const& item, Type2Type<MFLOAT>);  // 16
        virtual void slot17_editItemAt_float();
        virtual void slot18_itemAt_float();
        virtual void push_back(MINT64 const& item, Type2Type<MINT64>);  // 19
        // Slots 20..42 (i64 accessors, double, MRational, MPoint, MSize, MRect,
        // IMetadata, Memory) are never called from here and are left out.

    private:
        // FACT: the blob's constructor stores the vtable at +0 and a new'd
        // Implementor at +4 (IEntryC1Ej at 0x8ad8), so an entry is 8 bytes.
        // Kept so the declared layout is the real one; nothing here allocates.
        void* mImplementor;
    };

    virtual void slot00_complete_object_destructor();
    virtual void slot01_deleting_destructor();
    virtual MBOOL isEmpty() const;                                    // 2
    virtual MUINT count() const;                                      // 3
    virtual void slot04_clear();
    virtual void slot05_remove();
    virtual void slot06_sort();
    virtual MERROR update(MUINT32 tag, IEntry const& entry);          // 7
    virtual IEntry& editEntryFor(MUINT32 tag);                        // 8: aborts on a missing tag
    virtual IEntry const& entryFor(MUINT32 tag) const;                // 9: empty entry when missing
    // Slots 10..14 (editEntryAt, entryAt, flatten, unflatten, dump) unused.

private:
    void* mImplementor;
};

}  // namespace NSCam

// MediaTek's scaler tags mirror Android's: section 13, the same offsets.
// FACT for 0xd000a (checkStream loads it with movs/movt, libcam3_app 0x11760)
// and for all three here (built with movw/movt in the blob's IMX386_SUNNY scaler
// function, metastore 0x1a808). Values as in
// system/media/camera/include/system/camera_metadata_tags.h:324-326.
enum : NSCam::MUINT32 {
    MTK_SCALER_AVAILABLE_STREAM_CONFIGURATIONS = 0x000d000a,
    MTK_SCALER_AVAILABLE_MIN_FRAME_DURATIONS = 0x000d000b,
    MTK_SCALER_AVAILABLE_STALL_DURATIONS = 0x000d000c,
};

enum : NSCam::MINT32 {
    MTK_SCALER_AVAILABLE_STREAM_CONFIGURATIONS_OUTPUT = 0,
};
