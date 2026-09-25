/*
 * Add the streams the sensors can produce but their tables never list: RAW16 at
 * the rear pixel array, and 4:3 preview sizes between 640x480 and the stills.
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
 * The same tables stop at 640x480 for 4:3 below the stills, so an application
 * that wants a 4:3 viewfinder -- every Google Camera build -- gets 640x480 and
 * stretches it over a 1080-wide screen. The pipeline itself does better: on the
 * HAL1 path the stock preview was 1440x1080, with the pass-1 resizer at exactly
 * that size ("[decideRrzoImage] referenceSize:1440x1080 actual size:1440x1080",
 * P2 dump wdmao-1440x1080-1440_720_720-yv12, meizu_mx6_m95/
 * CAMERA_PREVIEW_WIDTH_TRIAGE.md). The rows are YCbCr_420_888 only:
 * MetadataProvider::updateData (metastore 0x4312e-0x431ec) copies every YUV
 * output row of 0xd000a/b/c into IMPLEMENTATION_DEFINED and YV12 rows after the
 * sensor sections have run, which is where the second 34 and the YV12 groups in
 * dumpsys come from. A PRIVATE preview stream is accepted by checkStream only
 * through such a row -- the validator patch lets unknown sizes through for YUV
 * alone.
 *
 * This library answers the call, and then hands it straight back. It resolves
 * the store's own implementation by name within the store itself, lets it fill
 * the metadata exactly as it always has, and only then appends rows.
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
 * whole rows into three tags and leaves everything else as the vendor left it;
 * if the vendor left those tags in a shape it does not recognise, it adds
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
 *  - Each addition has its own switch, persist.camera.raw and
 *    persist.camera.preview_43; with both off (or unset) the library is a
 *    pass-through.
 *  - All three tables are checked before any is edited. editEntryFor aborts on
 *    a tag that does not exist, and the LOS16 code only checked the first one.
 *  - The front sensor's section is answered too, for the 4:3 preview rows only.
 *    Appending to a vendor-built table proved itself on the rear (LOS20 build
 *    18: RAW row present, previews live); the front gets no raw row, because
 *    nothing on this device has shown its pipeline delivering one.
 */

#include <dlfcn.h>
#include <stddef.h>

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

typedef int (*ConstructFn)(IMetadata*, void const*);

const char* const kMetastore = "libmtkcam_metastore.so";
const char* const kRearSymbol =
        "constructCustStaticMetadata_DEVICE_SCALER_SENSOR_DRVNAME_IMX386_SUNNY_MIPI_RAW";
const char* const kFrontSymbol =
        "constructCustStaticMetadata_DEVICE_SCALER_SENSOR_DRVNAME_OV5695_MIPI_RAW";

// One output row as the three tags want it: the configuration (format, width,
// height, OUTPUT), its minimum frame duration and its stall duration.
struct Row {
    MINT32 format;
    MINT32 width;
    MINT32 height;
    MINT64 minFrameDuration;
    MINT64 stallDuration;
};

// The raw frame is the sensor's active array. Applications that use raw compare
// the size they are offered against that region and refuse a mismatch, which is
// why the vendor's own raw row for other sensors is at their native size too.
// The vendor publishes 33333333 for its own raw row on S5K2L7. It also decides
// which bucket the size lands in: the framework hides anything slower than
// twenty frames a second from getOutputSizes and offers it only through
// getHighResolutionOutputSizes, and an application that never asks the second
// question would never see raw at all.
const Row kRearRaw = {0x20 /* HAL_PIXEL_FORMAT_RAW16 */, 4032, 3016, 33333333LL, 33333333LL};

// 4:3 viewfinder sizes, YCbCr_420_888 at 30 fps and no stall, like the vendor's
// own YUV rows. 1440x1080 is the stock preview and the one a 1080-wide screen
// asks for; 1280x960 is the next step down for applications that cap below
// 1080 lines. Nothing taller than 1080: a viewfinder is chosen against the
// screen, and a larger buffer only costs the resizer and the GPU.
const Row kPreview43[] = {
        {0x23 /* YCbCr_420_888 */, 1440, 1080, 33333333LL, 0LL},
        {0x23 /* YCbCr_420_888 */, 1280, 960, 33333333LL, 0LL},
};

const MUINT kValuesPerRow = 4;

// A table the vendor left empty or ragged is one this library does not
// understand, and editEntryFor on a missing tag is an abort, not a create.
bool tableIsWhole(const IMetadata* metadata, MUINT32 tag) {
    const MUINT count = metadata->entryFor(tag).count();
    if (count == 0 || (count % kValuesPerRow) != 0) {
        ALOGE("tag 0x%x holds %u values; not appending", tag, count);
        return false;
    }
    return true;
}

template <typename T>
void appendValues(IMetadata* metadata, MUINT32 tag, T format, T width, T height, T last) {
    IMetadata::IEntry& entry = metadata->editEntryFor(tag);
    entry.push_back(format, Type2Type<T>());
    entry.push_back(width, Type2Type<T>());
    entry.push_back(height, Type2Type<T>());
    entry.push_back(last, Type2Type<T>());
}

void appendRow(IMetadata* metadata, const Row& row) {
    appendValues<MINT32>(metadata, MTK_SCALER_AVAILABLE_STREAM_CONFIGURATIONS, row.format,
                         row.width, row.height,
                         MTK_SCALER_AVAILABLE_STREAM_CONFIGURATIONS_OUTPUT);
    appendValues<MINT64>(metadata, MTK_SCALER_AVAILABLE_MIN_FRAME_DURATIONS, row.format,
                         row.width, row.height, row.minFrameDuration);
    appendValues<MINT64>(metadata, MTK_SCALER_AVAILABLE_STALL_DURATIONS, row.format,
                         row.width, row.height, row.stallDuration);
    ALOGI("appended format 0x%x %dx%d to the vendor table", row.format, row.width, row.height);
}

// Answer for one sensor section: run the store's own implementation, then append
// what the switches ask for. `self` is the exported answer calling this, so the
// lookup can tell the store's function from ours.
int extendSection(IMetadata* metadata, void const* info, const char* symbol, ConstructFn self,
                  bool rawAllowed) {
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

    ConstructFn vendor = reinterpret_cast<ConstructFn>(::dlsym(handle, symbol));
    ::dlclose(handle);
    if (vendor == NULL || vendor == self) {
        ALOGE("the store's own %s did not resolve; not touching the table", symbol);
        return -1;
    }

    // Which library actually answered, and did the metadata change? Both
    // questions have been guessed at once already; they are cheap to log.
    Dl_info where;
    if (::dladdr(reinterpret_cast<void*>(vendor), &where) != 0 && where.dli_fname != NULL) {
        ALOGI("%s: delegating to %p in %s", symbol, reinterpret_cast<void*>(vendor),
              where.dli_fname);
    } else {
        ALOGI("%s: delegating to %p, origin unknown", symbol, reinterpret_cast<void*>(vendor));
    }

    const int status = vendor(metadata, info);
    ALOGI("vendor returned %d; tag 0x%x now holds %u values", status,
          MTK_SCALER_AVAILABLE_STREAM_CONFIGURATIONS,
          metadata->entryFor(MTK_SCALER_AVAILABLE_STREAM_CONFIGURATIONS).count());

    // Off switches: read when the provider builds its static metadata, so they
    // take a provider restart, not a reflash. With both off the camera gets
    // exactly what the vendor built.
    const bool raw = rawAllowed && property_get_bool("persist.camera.raw", false);
    const bool preview43 = property_get_bool("persist.camera.preview_43", false);
    if (!raw && !preview43) {
        ALOGI("persist.camera.raw / preview_43 off; vendor table passed through");
        return status;
    }

    if (status == 0 &&
        tableIsWhole(metadata, MTK_SCALER_AVAILABLE_STREAM_CONFIGURATIONS) &&
        tableIsWhole(metadata, MTK_SCALER_AVAILABLE_MIN_FRAME_DURATIONS) &&
        tableIsWhole(metadata, MTK_SCALER_AVAILABLE_STALL_DURATIONS)) {
        if (raw) {
            appendRow(metadata, kRearRaw);
        }
        if (preview43) {
            for (size_t i = 0; i < sizeof(kPreview43) / sizeof(kPreview43[0]); ++i) {
                appendRow(metadata, kPreview43[i]);
            }
        }
    }
    return status;
}

}  // namespace

extern "C" __attribute__((visibility("default"))) int
constructCustStaticMetadata_DEVICE_SCALER_SENSOR_DRVNAME_IMX386_SUNNY_MIPI_RAW(
        IMetadata* metadata, void const* info) {
    return extendSection(metadata, info, kRearSymbol,
                         &constructCustStaticMetadata_DEVICE_SCALER_SENSOR_DRVNAME_IMX386_SUNNY_MIPI_RAW,
                         true);
}

extern "C" __attribute__((visibility("default"))) int
constructCustStaticMetadata_DEVICE_SCALER_SENSOR_DRVNAME_OV5695_MIPI_RAW(
        IMetadata* metadata, void const* info) {
    return extendSection(metadata, info, kFrontSymbol,
                         &constructCustStaticMetadata_DEVICE_SCALER_SENSOR_DRVNAME_OV5695_MIPI_RAW,
                         false);
}
