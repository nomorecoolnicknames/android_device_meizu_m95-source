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
 * a 24MB DNG came out of the probe -- but every preview on the phone went black
 * and the stock camera first crashed, then hung, and nobody noticed for hours
 * because the only thing being measured was a raw capture. The section sets
 * more than anyone had seen: the blob's IMX386_SUNNY function (metastore
 * 0x1a808) builds at least seven tags, among them the jpeg sizes as three MSize
 * values rather than int32 (push_back<MSize> at 0x1a848) and the maximum jpeg
 * size (0x70008) -- none of which a dump of the stream table shows.
 *
 * So this library never decides what the table should contain. It writes
 * exactly one row into three tags and leaves everything else as the vendor left
 * it; if the vendor left those tags in a shape it does not recognise, it adds
 * nothing and the camera gets exactly what it would have got without it.
 *
 * For our answer to be the one found, this library has to be global in the
 * provider process: bionic's dlsym(RTLD_DEFAULT) walks only RTLD_GLOBAL
 * libraries in load order, and falls back to the caller's own local group only
 * when that finds nothing (bionic/linker/linker.cpp dlsym_linear_lookup). The
 * store is loaded as a dependency of the dlopen'ed camera HAL, so it is local.
 * The library is a TARGET_LD_SHIM_LIBS shim of the provider executable
 * (BoardConfig.mk), which the linker loads RTLD_GLOBAL ahead of the
 * executable's own DT_NEEDED; LD_PRELOAD would be discarded, because the
 * provider starts with AT_SECURE set. Nothing in the blob is touched: renaming
 * its export would also put its own implementation out of reach, because the
 * lookup hash is built from the original strings.
 *
 * Changes from LOS16:
 *  - The NSCam declarations come from m95_nscam_metadata.h, decoded from the
 *    blob's vtables. In this blob entryFor() returns a reference; see there.
 *  - No link against any camera blob. The shim is linked before
 *    libmtkcam_metadata is in the process, and a symbol it cannot bind there
 *    stops the provider from starting at all.
 *  - The branch that published a whole section when the vendor's table came
 *    back empty is gone. Its data was a partial reconstruction (six tags, jpeg
 *    sizes as int32 where the blob writes MSize, no maximum jpeg size), and it
 *    was the branch live when previews went black.
 *  - persist.camera.raw=0 (or unset) is a pass-through.
 *  - All three tables are checked before any is edited. editEntryFor aborts on
 *    a tag that does not exist, and the LOS16 code only checked the first one.
 *  - The front sensor is not intercepted: nothing about its section has been
 *    measured, and an answer that goes wrong there takes the front camera down.
 */

#include <dlfcn.h>

#include <cutils/properties.h>
#include <log/log.h>

#include "m95_nscam_metadata.h"

#undef LOG_TAG
#define LOG_TAG "m95ScalerRaw"

using NSCam::IMetadata;
using NSCam::MINT32;
using NSCam::MINT64;
using NSCam::MUINT;
using NSCam::MUINT32;
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

const MUINT kValuesPerRow = 4;

typedef int (*ConstructFn)(IMetadata*, void const*);

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
    ALOGI("vendor returned %d; tag 0x%x now holds %u values", status,
          MTK_SCALER_AVAILABLE_STREAM_CONFIGURATIONS,
          metadata->entryFor(MTK_SCALER_AVAILABLE_STREAM_CONFIGURATIONS).count());

    // Off switch: with the property at 0 this library is a pass-through and the
    // camera gets exactly what the vendor built. Read when the provider builds
    // its static metadata, so it takes a provider restart, not a reflash.
    if (!property_get_bool("persist.camera.raw", false)) {
        ALOGI("persist.camera.raw is off; vendor table passed through");
        return status;
    }

    if (status == 0 &&
        tableIsWhole(metadata, MTK_SCALER_AVAILABLE_STREAM_CONFIGURATIONS) &&
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
