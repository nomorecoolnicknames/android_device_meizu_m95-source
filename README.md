# Meizu MX6 (M95)

**LineageOS 20.0 · Android 13 · ARM64**

Device configuration and compatibility code maintained by [ReMeizu](https://github.com/nomorecoolnicknames/remeizu).

| Target | Configuration |
| --- | --- |
| Product | `lineage_m95-userdebug` |
| Device path | `device/meizu/m95` |
| Platform | MT6797 / Helio X20 |
| Display | 1080 × 1920 |
| Kernel route | 3.18 prebuilt; `lineage_m95_defconfig` headers |

## Status

Native Android 13 boots on MX6. Hardware testing of build 23 on 2026-09-26 observed LTE data and IMS registration. Incoming IMS calls still crashed; the subsequent call-handling and camera changes need device testing. Those earlier hardware observations predate this source tip. Full native ROM build 31 completed on 5 October 2026; the subsequent hotplug, consumer IR permissions and thermal service source changes are not a new full hardware acceptance pass.

| Stage | Result |
| --- | --- |
| Source | Device tree, source HALs and compatibility shims available |
| Build | Native LOS20 build 31 completed on 5 October; later source changes await full acceptance |
| Hardware | Boot and LTE data observed; camera lifecycle, IMS calls and sustained power/thermal behaviour remain open |

## Components

| Subsystem | Implementation / source | Availability | Working status |
| --- | --- | --- | --- |
| Boot / storage | [BoardConfig.mk](BoardConfig.mk) · [rootdir/Android.mk](rootdir/Android.mk) | Config; kernel image external | Boot observed in build 23 |
| Display / GPU | [shims/region.cpp](shims/region.cpp) · MTK HWC/Mali vendor libraries | ABI adapter source; GPU/HWC blobs external | Display usable in earlier LOS20 builds |
| Wi-Fi | [wifi_hal](wifi_hal) · [wpa_supplicant_8_lib](wpa_supplicant_8_lib) · [rootdir/init.m95.connectivity.rc](rootdir/init.m95.connectivity.rc) | HAL wrapper and configuration; firmware external | 2.4/5 GHz scans observed; connection not tested |
| Bluetooth | [shims/Android.bp](shims/Android.bp) (`libm95shim_btvendor`) · [rootdir/init.m95.connectivity.rc](rootdir/init.m95.connectivity.rc) | Adapter source; stock transport external | Enabled in earlier builds; pairing/audio unverified |
| Radio / LTE / IMS | [shims/nparcel.cpp](shims/nparcel.cpp) · [rootdir/init.m95.modem.rc](rootdir/init.m95.modem.rc) | Parcel adapter and init; modem/RIL/IMS inputs external | LTE data and IMS registration observed; IMS calls incomplete |
| Camera | [camera_metadata_raw](camera_metadata_raw) · [shims/Android.bp](shims/Android.bp) · [gcam](gcam) | Compatibility/metadata code; sensor HAL external | Photos/preview observed; close/reopen crashes and frame delivery remain open |
| Audio | [audio/audio_policy_configuration.xml](audio/audio_policy_configuration.xml) · [shims/Android.bp](shims/Android.bp) | Policy/adapters; primary HAL external | Call audio reported in earlier tests; full media/routing coverage pending |
| Sensors | [rootdir/init.m95.sensors.rc](rootdir/init.m95.sensors.rc) · [shims/Android.bp](shims/Android.bp) | Init/ABI adapters; sensor HAL external | Accelerometer events observed; proximity during calls incomplete |
| Fingerprint | [fingerprint](fingerprint) | Service wrapper source; stock HAL/TEE external | Unlock reported; repeatable enrollment/unlock coverage pending |
| Lights | [lights/lights.c](lights/lights.c) | HAL source | Backlight/LED functional coverage unverified |
| GPS | [shims/Android.bp](shims/Android.bp) (`libm95shim_ssl`, `libm95shim_mnld`) | Adapters; GNSS daemon/firmware external | Earlier GNSS crash fixes need a verified location fix |
| Thermal | [thermal](thermal) | Source HAL 2.0 exposing only real sensor readings; no fabricated trip thresholds | Compiled/service integration requires physical temperature and throttling validation |
| Power / security | [BoardConfig.mk](BoardConfig.mk) · [sepolicy](sepolicy) | Kernel/HAL configuration and policy | Suspend/thermal tests open; enforcing and encryption incomplete |

## Build

Use a matching LineageOS 20.0 source tree and place this checkout at `device/meizu/m95`. Provide these inputs before running lunch:

| Input | Location / requirement |
| --- | --- |
| Platform compatibility | Matching legacy MediaTek framework/HAL adaptations; this device tree alone is not the platform |
| Vendor inputs | Prepared `vendor/meizu/m95` tree matching this device and branch |
| Stock init / fstab inputs | Supply the missing `rootdir/init.mt6797.rc`, `init.mt6797.usb.rc`, `goodixfpd.rc`, `fstab.mt6797` and `ueventd.mt6797.rc` referenced by `rootdir/Android.mk`, plus stock keylayout/media inputs from `device.mk` |
| Kernel source / headers | `kernel/meizu/m95` |
| Kernel image | `device/meizu/m95/prebuilt/Image.gz-dtb`; use the matching board kernel and DTB |

The vendor tree must retain the branch’s compatibility transformations and symlinks; a raw extraction is not interchangeable with the prepared vendor tree. `setup-makefiles.sh` protects hand-maintained vendor makefiles. The default product expects GCam inputs; `M95_WITHOUT_GCAM=true` omits that package.

```sh
source build/envsetup.sh
lunch lineage_m95-userdebug
m -j4 bacon
```

## Next steps

- Validate the incoming IMS-call fix, outgoing VoLTE and SMS-over-IMS.
- Finish camera close/reopen and frame-delivery tests, then suspend, charging and sustained thermal tests.

The [ReMeizu overview](https://github.com/nomorecoolnicknames/remeizu/blob/main/PROJECT_STATUS.md) tracks the broader project; the [source index](https://github.com/nomorecoolnicknames/remeizu/blob/main/SOURCE_INDEX.md) links device, common and kernel trees.

## Credits

LineageOS and CyanogenMod contributors, the original device-tree authors, and ReMeizu contributors. Copyright and license notices remain with their source files.

## Current integration changes

Legacy camera Looper storage is allocated for the matching vendor ABI. Optional hotplug tuning is exposed through `persist.vendor.m95.hps` only with a kernel that implements the corresponding hotplug fixes. Consumer IR policy permits the source HAL to access `/dev/irtx`. The thermal HAL reads actual available sensors and does not invent thermal thresholds. These changes do not establish smooth GCam frame delivery, stable IMS calls, working Wi-Fi VHT or safe sustained thermals.

Public builds use no pretrusted workstation ADB keys by default. Supply `M95_ADB_KEYS` explicitly only when required for your own test environment. Camera APKs remain separately supplied inputs; `gcam/fetch-gcam.sh` requires the caller's directory and verifies pinned hashes before unpacking.
