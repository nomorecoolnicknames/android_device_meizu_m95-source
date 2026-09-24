/*
 * Add the raw stream the rear sensor can produce but its table never lists.
 *
 * Ported from the LOS16 tree (meizu_mx6_m95/los/device/meizu/m95/
 * camera_metadata_raw, last change f8036f9). What changed on the way is listed
 * at the end of this comment; the reasoning below is the LOS16 one and still
 * holds.
 *
 * MediaTek's metadata store does not hold the per-sensor stream table as data.
 * It asks for it: MetadataProvider builds a symbol name from the sensor's driver
 * name and calls dlsym(RTLD_DEFAULT, ...) for
 *
 *   constructCustStaticMetadata_DEVICE_SCALER_SENSOR_DRVNAME_<driver>
 *
 * and uses whoever answers first. The section shipped for IMX386_SUNNY carries
 * JPEG, YUV and implementation-defined rows and not one raw row, so
 * android.scaler.availableStreamConfigurations reaches the framework without a
 * raw entry -- and, what matters more, so does the vendor's own copy of that
 * tag, the one AppStreamMgr::checkStream and the pipeline read. The omission is
 * in that one table, not in the sensor: the same library authorises raw for
 * S5K2L7 at its native 4032x3024, and on LOS16 a RAW16 4032x3016 frame arrived
 * and a 24MB DNG was written while this row was present (2026-08-19).
 *
 * This library answers the call, and then hands it straight back. It resolves
 * the store's own implementation by name within the store itself, lets it fill
 * the metadata exactly as it always has, and only then appends the raw rows.
 *
 * Appending rather than replacing is the whole point, and it was learned the
 * expensive way. An earlier version renamed the blob's export and published a
 * whole table read back from a running handset. It looked right -- raw arrived,
 * a 24MB DNG came out of the probe -- but that section sets six tags and the
 * reproduction carried three. The missing availableMaxDigitalZoom is a float,
 * and an absent float is a null rather than a zero, so the stock camera called
 * floatValue() on nothing and died; with that restored it hung instead. That
 * version also handed the front sensor the rear's table, so which of the two
 * caused the hang was never separated. Every preview on the phone went black
 * and nobody noticed for hours, because the only thing being measured was a raw
 * capture -- one stream, no preview, the single case that kept working.
 *
 * So this version never decides what the table should contain when the vendor
 * has filled it. It writes exactly one row into three tags and leaves
 * everything else as the vendor left it.
 *
 * For our answer to be the one found, this library has to be global in the
 * provider process: bionic's dlsym(RTLD_DEFAULT) walks only RTLD_GLOBAL
 * libraries in load order, and falls back to the caller's own local group only
 * when that finds nothing (bionic/linker/linker.cpp dlsym_linear_lookup). The
 * store is loaded as a dependency of the dlopen'ed camera HAL, so it is local,
 * and a preloaded library wins regardless of when the store arrives. That is
 * arranged by LD_PRELOAD on the provider service (init.m95.camera-provider.rc),
 * not by touching the blob: renaming its export would also put its own
 * implementation out of reach, because the lookup hash is built from the
 * original strings.
 *
 * Changes from LOS16:
 *  - The NSCam declarations come from m95_nscam_metadata.h, decoded from the
 *    blob's vtables. In this blob entryFor() returns a reference; see there.
 *  - No link against libmtkcam_metadata. A preloaded library is relocated
 *    before that blob is in the process, so any symbol taken from it by link
 *    would be unresolvable and the preload would be dropped.
 *  - persist.camera.raw=0 is now a real off switch: the vendor's result passes
 *    through untouched. It used to still carry the whole section when the
 *    vendor left it empty.
 *  - All three tables are checked before any is edited. editEntryFor aborts on
 *    a tag that does not exist, and the LOS16 code only checked the first one.
 *  - The front sensor is not intercepted. Its section has no known-good copy to
 *    fall back on, and an answer that leaves its table empty would take the
 *    front camera down with it.
 */

#include <dlfcn.h>
#include <stddef.h>

#include <cutils/properties.h>
#include <log/log.h>

#include "m95_nscam_metadata.h"

#undef LOG_TAG
#define LOG_TAG "m95ScalerRaw"

using NSCam::IMetadata;
using NSCam::MFLOAT;
using NSCam::MINT32;
using NSCam::MINT64;
using NSCam::MUINT;
using NSCam::MUINT32;
using NSCam::MUINT8;
using NSCam::Type2Type;

namespace {

const char* const kMetastore = "libmtkcam_metastore.so";
const char* const kSymbol =
        "constructCustStaticMetadata_DEVICE_SCALER_SENSOR_DRVNAME_IMX386_SUNNY_MIPI_RAW";

// The raw frame is the sensor's active array. Applications that use raw compare
// the size they are offered against that region and refuse a mismatch, which is
// why the vendor's own raw row for other sensors is at their native size too.
const MINT32 kRawFormat = 0x20;  // HAL_PIXEL_FORMAT_RAW16
const MINT32 kRawWidth = 4032;
const MINT32 kRawHeight = 3016;

// The vendor publishes 33333333 for its own raw row on S5K2L7. It also decides
// which bucket the size lands in: the framework hides anything slower than
// twenty frames a second from getOutputSizes and offers it only through
// getHighResolutionOutputSizes, and an application that never asks the second
// question would never see raw at all.
const MINT64 kRawFrameDuration = 33333333LL;
const MINT64 kRawStallDuration = 33333333LL;

// The vendor's own rows, read back from a running handset before any of this
// existed (LOS16, the same blob). They are used only when the vendor's function
// reports success and leaves the table empty; see the end of the entry point.
static const MINT32 kStreamConfigs[] = {
        33, 4096, 3072, 0,
        33, 4096, 2304, 0,
        33, 3264, 2448, 0,
        33, 3840, 2160, 0,
        33, 2560, 1920, 0,
        33, 1920, 1088, 0,
        33, 1280, 720, 0,
        33, 640, 480, 0,
        33, 320, 240, 0,
        35, 1920, 1088, 0,
        35, 1920, 1080, 0,
        35, 1280, 720, 0,
        35, 720, 480, 0,
        35, 640, 480, 0,
        35, 352, 288, 0,
        35, 320, 240, 0,
        35, 176, 144, 0,
        34, 1920, 1088, 0,
        34, 1920, 1080, 0,
        34, 1280, 720, 0,
        34, 720, 480, 0,
        34, 640, 480, 0,
        34, 352, 288, 0,
        34, 320, 240, 0,
        34, 176, 144, 0,
        34, 1920, 1088, 0,
        34, 1920, 1080, 0,
        34, 1280, 720, 0,
        34, 720, 480, 0,
        34, 640, 480, 0,
        34, 352, 288, 0,
        34, 320, 240, 0,
        34, 176, 144, 0,
        842094169, 1920, 1088, 0,
        842094169, 1920, 1080, 0,
        842094169, 1280, 720, 0,
        842094169, 720, 480, 0,
        842094169, 640, 480, 0,
        842094169, 352, 288, 0,
        842094169, 320, 240, 0,
        842094169, 176, 144, 0,
};

static const MINT64 kMinFrameDurations[] = {
        33LL, 4096LL, 3072LL, 66666666LL,
        33LL, 4096LL, 2304LL, 66666666LL,
        33LL, 3264LL, 2448LL, 50000000LL,
        33LL, 3840LL, 2160LL, 50000000LL,
        33LL, 2560LL, 1920LL, 33333333LL,
        33LL, 1920LL, 1088LL, 33333333LL,
        33LL, 1280LL, 720LL, 33333333LL,
        33LL, 640LL, 480LL, 33333333LL,
        33LL, 320LL, 240LL, 33333333LL,
        35LL, 1920LL, 1088LL, 33333333LL,
        35LL, 1920LL, 1080LL, 33333333LL,
        35LL, 1280LL, 720LL, 33333333LL,
        35LL, 720LL, 480LL, 33333333LL,
        35LL, 640LL, 480LL, 33333333LL,
        35LL, 352LL, 288LL, 33333333LL,
        35LL, 320LL, 240LL, 33333333LL,
        35LL, 176LL, 144LL, 33333333LL,
        34LL, 1920LL, 1088LL, 33333333LL,
        34LL, 1920LL, 1080LL, 33333333LL,
        34LL, 1280LL, 720LL, 33333333LL,
        34LL, 720LL, 480LL, 33333333LL,
        34LL, 640LL, 480LL, 33333333LL,
        34LL, 352LL, 288LL, 33333333LL,
        34LL, 320LL, 240LL, 33333333LL,
        34LL, 176LL, 144LL, 33333333LL,
        34LL, 320LL, 240LL, 33333333LL,
        34LL, 176LL, 144LL, 33333333LL,
        34LL, 1920LL, 1088LL, 33333333LL,
        34LL, 1920LL, 1080LL, 33333333LL,
        34LL, 1280LL, 720LL, 33333333LL,
        34LL, 720LL, 480LL, 33333333LL,
        34LL, 640LL, 480LL, 33333333LL,
        34LL, 352LL, 288LL, 33333333LL,
        34LL, 320LL, 240LL, 33333333LL,
        34LL, 176LL, 144LL, 33333333LL,
        842094169LL, 1920LL, 1088LL, 33333333LL,
        842094169LL, 1920LL, 1080LL, 33333333LL,
        842094169LL, 1280LL, 720LL, 33333333LL,
        842094169LL, 720LL, 480LL, 33333333LL,
        842094169LL, 640LL, 480LL, 33333333LL,
        842094169LL, 352LL, 288LL, 33333333LL,
        842094169LL, 320LL, 240LL, 33333333LL,
        842094169LL, 176LL, 144LL, 33333333LL,
};

static const MINT64 kStallDurations[] = {
        33LL, 4096LL, 3072LL, 33333333LL,
        33LL, 4096LL, 2304LL, 33333333LL,
        33LL, 3264LL, 2448LL, 33333333LL,
        33LL, 3840LL, 2160LL, 33333333LL,
        33LL, 2560LL, 1920LL, 33333333LL,
        33LL, 1920LL, 1088LL, 33333333LL,
        33LL, 1280LL, 720LL, 33333333LL,
        33LL, 640LL, 480LL, 33333333LL,
        33LL, 320LL, 240LL, 33333333LL,
        35LL, 1920LL, 1088LL, 0LL,
        35LL, 1920LL, 1080LL, 0LL,
        35LL, 1280LL, 720LL, 0LL,
        35LL, 720LL, 480LL, 0LL,
        35LL, 640LL, 480LL, 0LL,
        35LL, 352LL, 288LL, 0LL,
        35LL, 320LL, 240LL, 0LL,
        35LL, 176LL, 144LL, 0LL,
        34LL, 1920LL, 1088LL, 0LL,
        34LL, 1920LL, 1080LL, 0LL,
        34LL, 1280LL, 720LL, 0LL,
        34LL, 720LL, 480LL, 0LL,
        34LL, 640LL, 480LL, 0LL,
        34LL, 352LL, 288LL, 0LL,
        34LL, 320LL, 240LL, 0LL,
        34LL, 176LL, 144LL, 0LL,
        34LL, 1920LL, 1088LL, 0LL,
        34LL, 1920LL, 1080LL, 0LL,
        34LL, 1280LL, 720LL, 0LL,
        34LL, 720LL, 480LL, 0LL,
        34LL, 640LL, 480LL, 0LL,
        34LL, 352LL, 288LL, 0LL,
        34LL, 320LL, 240LL, 0LL,
        34LL, 176LL, 144LL, 0LL,
        842094169LL, 1920LL, 1088LL, 0LL,
        842094169LL, 1920LL, 1080LL, 0LL,
        842094169LL, 1280LL, 720LL, 0LL,
        842094169LL, 720LL, 480LL, 0LL,
        842094169LL, 640LL, 480LL, 0LL,
        842094169LL, 352LL, 288LL, 0LL,
        842094169LL, 320LL, 240LL, 0LL,
        842094169LL, 176LL, 144LL, 0LL,
};

// All six are published together on purpose. An earlier version wrote only the
// three tables and left the other three tags empty; the missing digital-zoom
// figure is a float, and an absent float reads as null rather than zero, which
// is what the stock camera called floatValue() on before dying.
static const MINT32 kJpegSizes[] = {800, 600, 1600, 1200, 2560, 1920};
static const MFLOAT kMaxDigitalZoom = 16.0f;

const MUINT kValuesPerRow = 4;

typedef int (*ConstructFn)(IMetadata*, void const*);

// Building an entry needs the vendor's constructor, the one thing here that is
// not a virtual call. It and the destructor are taken by name at run time: this
// library is mapped by LD_PRELOAD before libmtkcam_metadata is in the process,
// so linking them would leave two relocations bionic cannot bind at preload.
typedef void* (*EntryCtor)(void* self, MUINT32 tag);
typedef void* (*EntryDtor)(void* self);

const char* const kMetadataLib = "libmtkcam_metadata.so";
const char* const kEntryCtor = "_ZN5NSCam9IMetadata6IEntryC1Ej";
const char* const kEntryDtor = "_ZN5NSCam9IMetadata6IEntryD1Ev";

// An entry is 8 bytes on this blob (vtable, Implementor*); the room below is
// far more than that, and the constructor is the only thing that writes into it.
union EntryStorage {
    unsigned char bytes[64];
    void* alignment[8];
};

class ScopedEntry {
public:
    ScopedEntry() : mDtor(NULL), mEntry(NULL) {}

    bool create(MUINT32 tag) {
        // RTLD_NOLOAD: the store needs this library, so it is here whenever the
        // store calls us. If it is somehow not, loading a copy is not our call.
        void* handle = ::dlopen(kMetadataLib, RTLD_NOW | RTLD_NOLOAD);
        if (handle == NULL) {
            ALOGE("%s is not loaded: %s", kMetadataLib, ::dlerror());
            return false;
        }
        EntryCtor ctor = reinterpret_cast<EntryCtor>(::dlsym(handle, kEntryCtor));
        mDtor = reinterpret_cast<EntryDtor>(::dlsym(handle, kEntryDtor));
        ::dlclose(handle);
        if (ctor == NULL || mDtor == NULL) {
            ALOGE("%s exports no entry constructor or destructor", kMetadataLib);
            mDtor = NULL;
            return false;
        }
        __builtin_memset(&mStorage, 0, sizeof(mStorage));
        ctor(&mStorage, tag);
        mEntry = reinterpret_cast<IMetadata::IEntry*>(&mStorage);
        return true;
    }

    ~ScopedEntry() {
        if (mDtor != NULL && mEntry != NULL) {
            mDtor(&mStorage);
        }
    }

    IMetadata::IEntry* get() { return mEntry; }

private:
    EntryStorage mStorage;
    EntryDtor mDtor;
    IMetadata::IEntry* mEntry;
};

template <typename T>
bool publish(IMetadata* metadata, MUINT32 tag, const T* rows, size_t count, T rawFormat,
             T rawWidth, T rawHeight, T rawLast, bool withRaw) {
    ScopedEntry entry;
    if (!entry.create(tag)) {
        return false;
    }
    for (size_t i = 0; i < count; ++i) {
        entry.get()->push_back(rows[i], Type2Type<T>());
    }
    if (withRaw) {
        entry.get()->push_back(rawFormat, Type2Type<T>());
        entry.get()->push_back(rawWidth, Type2Type<T>());
        entry.get()->push_back(rawHeight, Type2Type<T>());
        entry.get()->push_back(rawLast, Type2Type<T>());
    }
    metadata->update(tag, *entry.get());
    return true;
}

// A table the vendor left empty or ragged is one this library does not
// understand, and editEntryFor on a missing tag is an abort, not a create.
bool tableIsWhole(const IMetadata* metadata, MUINT32 tag) {
    const MUINT count = metadata->entryFor(tag).count();
    if (count == 0 || (count % kValuesPerRow) != 0) {
        ALOGE("tag 0x%x holds %u values; not appending raw", tag, count);
        return false;
    }
    return true;
}

template <typename T>
void appendRow(IMetadata* metadata, MUINT32 tag, T format, T width, T height, T last) {
    IMetadata::IEntry& entry = metadata->editEntryFor(tag);
    entry.push_back(format, Type2Type<T>());
    entry.push_back(width, Type2Type<T>());
    entry.push_back(height, Type2Type<T>());
    entry.push_back(last, Type2Type<T>());
}

}  // namespace

extern "C" __attribute__((visibility("default"))) int
constructCustStaticMetadata_DEVICE_SCALER_SENSOR_DRVNAME_IMX386_SUNNY_MIPI_RAW(
        IMetadata* metadata, void const* info) {
    if (metadata == NULL) {
        return -1;
    }

    // RTLD_NOLOAD: the store is the one asking, so it is already here. Looking
    // the symbol up through its handle rather than the default scope is what
    // reaches its implementation instead of this one.
    void* handle = ::dlopen(kMetastore, RTLD_NOW | RTLD_NOLOAD);
    if (handle == NULL) {
        ALOGE("%s is not loaded; leaving the table to whoever else answers", kMetastore);
        return -1;
    }

    ConstructFn vendor = reinterpret_cast<ConstructFn>(::dlsym(handle, kSymbol));
    ::dlclose(handle);
    if (vendor == NULL ||
        vendor == &constructCustStaticMetadata_DEVICE_SCALER_SENSOR_DRVNAME_IMX386_SUNNY_MIPI_RAW) {
        ALOGE("the store's own %s did not resolve; not touching the table", kSymbol);
        return -1;
    }

    // Which library actually answered, and did the metadata change? Both
    // questions have been guessed at once already; they are cheap to log.
    Dl_info where;
    if (::dladdr(reinterpret_cast<void*>(vendor), &where) != 0 && where.dli_fname != NULL) {
        ALOGI("delegating to %p in %s", reinterpret_cast<void*>(vendor), where.dli_fname);
    } else {
        ALOGI("delegating to %p, origin unknown", reinterpret_cast<void*>(vendor));
    }

    const int status = vendor(metadata, info);
    const MUINT vendorRows = metadata->entryFor(MTK_SCALER_AVAILABLE_STREAM_CONFIGURATIONS).count();
    ALOGI("vendor returned %d; tag 0x%x now holds %u values", status,
          MTK_SCALER_AVAILABLE_STREAM_CONFIGURATIONS, vendorRows);

    // Off switch: with the property at 0 this library is a pass-through and the
    // camera gets exactly what the vendor built. Read when the provider builds
    // its static metadata, so it takes a provider restart, not a reflash.
    if (!property_get_bool("persist.camera.raw", false)) {
        ALOGI("persist.camera.raw is off; vendor table passed through");
        return status;
    }

    // The expected path: the vendor filled its tables and we only add a row.
    if (vendorRows > 0) {
        if (tableIsWhole(metadata, MTK_SCALER_AVAILABLE_STREAM_CONFIGURATIONS) &&
            tableIsWhole(metadata, MTK_SCALER_AVAILABLE_MIN_FRAME_DURATIONS) &&
            tableIsWhole(metadata, MTK_SCALER_AVAILABLE_STALL_DURATIONS)) {
            appendRow<MINT32>(metadata, MTK_SCALER_AVAILABLE_STREAM_CONFIGURATIONS, kRawFormat,
                              kRawWidth, kRawHeight,
                              MTK_SCALER_AVAILABLE_STREAM_CONFIGURATIONS_OUTPUT);
            appendRow<MINT64>(metadata, MTK_SCALER_AVAILABLE_MIN_FRAME_DURATIONS, kRawFormat,
                              kRawWidth, kRawHeight, kRawFrameDuration);
            appendRow<MINT64>(metadata, MTK_SCALER_AVAILABLE_STALL_DURATIONS, kRawFormat,
                              kRawWidth, kRawHeight, kRawStallDuration);
            ALOGI("raw %dx%d appended to the vendor table", kRawWidth, kRawHeight);
        }
        return status;
    }

    // The LOS16 comment for this branch reads "the real path, as measured:
    // nothing was written" -- but no log of that measurement survives, and the
    // vendor function builds its rows with update() (metastore-raw-patch.md), so
    // an empty table here is unexpected. If it happens anyway, carry the whole
    // section, the vendor's six tags plus the raw row, rather than leave the
    // back camera with no stream table at all. This is the branch that was live
    // when previews went black on LOS16; if they go black again, the log line
    // below says this branch ran, and persist.camera.raw=0 takes it out.
    publish<MINT32>(metadata, MTK_SCALER_AVAILABLE_STREAM_CONFIGURATIONS, kStreamConfigs,
                    sizeof(kStreamConfigs) / sizeof(kStreamConfigs[0]), kRawFormat, kRawWidth,
                    kRawHeight, MTK_SCALER_AVAILABLE_STREAM_CONFIGURATIONS_OUTPUT, true);
    publish<MINT64>(metadata, MTK_SCALER_AVAILABLE_MIN_FRAME_DURATIONS, kMinFrameDurations,
                    sizeof(kMinFrameDurations) / sizeof(kMinFrameDurations[0]), kRawFormat,
                    kRawWidth, kRawHeight, kRawFrameDuration, true);
    publish<MINT64>(metadata, MTK_SCALER_AVAILABLE_STALL_DURATIONS, kStallDurations,
                    sizeof(kStallDurations) / sizeof(kStallDurations[0]), kRawFormat, kRawWidth,
                    kRawHeight, kRawStallDuration, true);

    {
        ScopedEntry jpeg;
        if (jpeg.create(MTK_SCALER_AVAILABLE_JPEG_SIZES)) {
            for (size_t k = 0; k < sizeof(kJpegSizes) / sizeof(kJpegSizes[0]); ++k) {
                jpeg.get()->push_back(kJpegSizes[k], Type2Type<MINT32>());
            }
            metadata->update(MTK_SCALER_AVAILABLE_JPEG_SIZES, *jpeg.get());
        }

        ScopedEntry zoom;
        if (zoom.create(MTK_SCALER_AVAILABLE_MAX_DIGITAL_ZOOM)) {
            zoom.get()->push_back(kMaxDigitalZoom, Type2Type<MFLOAT>());
            metadata->update(MTK_SCALER_AVAILABLE_MAX_DIGITAL_ZOOM, *zoom.get());
        }

        ScopedEntry crop;
        if (crop.create(MTK_SCALER_CROPPING_TYPE)) {
            const MUINT8 freeform = MTK_SCALER_CROPPING_TYPE_FREEFORM;
            crop.get()->push_back(freeform, Type2Type<MUINT8>());
            metadata->update(MTK_SCALER_CROPPING_TYPE, *crop.get());
        }
    }

    ALOGW("vendor left the scaler table empty; carried the whole section with raw %dx%d",
          kRawWidth, kRawHeight);
    return 0;
}
