#
# device.mk — Meizu MX6 (m95, MT6797) on LineageOS 20 (Android 13, SDK 33).
#
# Ported from the LineageOS 18.1 tree of this same device
# (meizu_mx6_m95/device-18.1/meizu/m95/device.mk), which is the newest tree that
# actually booted this handset.  Every deletion and every substitution relative
# to that file is justified in meizu-fleet/trees/M95_LOS20_TREE.md.
#
# SPDX-License-Identifier: Apache-2.0
#

LOCAL_PATH := device/meizu/m95

# ---------------------------------------------------------------------------
# Soong namespaces (device-tree isolation)
#
# FACT (measured 2026-09-16): Soong parses every Android.bp in the workspace
# for every product and has no TARGET_DEVICE guard, so a bp module declared in
# one device tree lands in installs-<product>.mk of ALL products — a plain
# `m nothing` for lineage_m5s carried 51 install-rule lines from
# device/meizu/m95 (27 modules), two of them colliding with real m5s blobs
# (vendor/lib{,64}/libperfservicenative.so, via the `stem:` of
# libm95shim_perfservice).  Modules of a namespace reach Make only for the
# products that list that namespace here
# (build/soong/cmd/soong_build/main.go:99-112 -> android/namespace.go:204 ->
# android/androidmk.go:919).  Each tree carries a root Android.bp with
# `soong_namespace {}`; this line is the other half of the pair.
# ---------------------------------------------------------------------------
PRODUCT_SOONG_NAMESPACES += \
    device/meizu/m95 \
    vendor/meizu/m95

# Ship the v30 VNDK apex next to the current (v33) one.  Two reasons, both
# concrete: (a) the vendor image this port already has was built on Android 11
# and declares ro.vndk.version=30 — with com.android.vndk.v30 present this
# system image can be booted against it unchanged, which is the exact
# configuration in which the handset reached the launcher on 2026-09-11;
# (b) it is what the Android 13 GSI does
# (build/make/target/product/gsi_release.mk:66).
# The apex is pulled in by vndk_apex_snapshot_package
# (build/make/target/product/gsi/Android.mk:191-204).
PRODUCT_EXTRA_VNDK_VERSIONS := 30

# ---------------------------------------------------------------------------
# Vendor public libraries: the stock list plus libwfo_jni.so for ForgeImsService
# (reasoning inside the file).  This line MUST stay above the inherit of
# m95-vendor.mk: that makefile copies the stock file to the same destination,
# and for PRODUCT_COPY_FILES the FIRST entry for a destination wins
# (build/make/core/Makefile:70-89); an inherit-product expands in place, so
# anything written below it comes after the vendor's own entry and is dropped
# into product_copy_files_ignored.txt.
#
# Why the ImsService needs it: on 18.1 (VNDK-lite) the system default namespace
# searched /vendor/${LIB}; Android 13 has no VNDK-lite (system/linkerconfig
# main.cc:365), so without this entry loadLibrary("wfo_jni") fails with
# "library not found" and MAL's ePDG entity never learns the SIM.
# ---------------------------------------------------------------------------
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/configs/public.libraries-vendor.txt:$(TARGET_COPY_OUT_VENDOR)/etc/public.libraries.txt

# ---------------------------------------------------------------------------
# Vendor blobs (real /vendor image on the `custom` partition)
# ---------------------------------------------------------------------------
$(call inherit-product, vendor/meizu/m95/m95-vendor.mk)
$(call inherit-product, vendor/meizu/m95/m95-vendor-extra.mk)

# Vendor prebuilt modules (vendor/meizu/m95/Android.mk).
PRODUCT_PACKAGES += \
    vulkan.mt6797_symlinks \
    librilimp

# RIL instance-unification, as on 18.1 (A11_BRINGUP_STATE.md §2m,
# SIM_LANE_STATE.md).  Our patched libril is emitted a second time under the
# soname the vendor blob already needs, librilmtk.so, so mtk-ril.so's
# RIL_onRequestComplete binds to OUR pending-request list; rild links it
# instead of libril.  librilimp (above) is the stock MTK libril, renamed, for
# the 11 modem-internal symbols we do not implement.  64-bit only.  The module
# comes from hardware/ril branch meizu-legacy-vendor under
# BOARD_USES_MTK_LEGACY_RIL (BoardConfig.mk); rild would pull it in anyway,
# the name here documents the dependency.  It does NOT make a tree without
# that branch fail (PRODUCT_ENFORCE_PACKAGES_EXIST is not set): the guard for
# that is the $(error) next to the flag in BoardConfig.mk.
PRODUCT_PACKAGES += \
    librilmtk

# libstdc++ (bionic's small one) as a VENDOR copy: the 32-bit Mali closure
# (libGLES_mali -> ... -> libvcodec_oal.so) needs it, and it is neither LLNDK
# nor VNDK, so a vendor process cannot see the /system/lib copy.
# 2026-09-06 (18.1): "library libstdc++.so not found: needed by
# /vendor/lib/libvcodec_oal.so in namespace sphal" aborted zygote_secondary on
# every start.  bionic/libc/Android.bp:2034 still has vendor_available: true on
# Android 13, so the .vendor variant is a real module here too.
PRODUCT_PACKAGES += \
    libstdc++.vendor

# Vendor copies of two non-VNDK framework libraries the N blobs link against.
# libgui_vendor is an upstream AOSP 13 module (frameworks/native/libs/gui/
# Android.bp:420, cc_library_shared + vendor: true); libsensor_vendor comes from
# hardware/lineage/compat/Android.bp:383.  On 18.1 these had to be hand-added.
#
# The blobs do not NEED them by these names: they were rewired on 18.1 to
# libgui_m95.so / libsensor_m95.so, and nothing provided those here (FACT,
# staging vendor/ of 2026-09-16: 47 consumers, hwcomposer.mt6797.so among
# them, would fail with `library "libgui_m95.so" not found`).  libgui_m95 and
# libsensor_m95 are empty forwarders with DT_NEEDED on the real library
# (shims/Android.bp explains why not a symlink or a second libgui).
PRODUCT_PACKAGES += \
    libgui_vendor \
    libsensor_vendor \
    libgui_m95 \
    libsensor_m95

# Vendor libcamera_client (frameworks/av/camera, branch meizu-legacy-vendor):
# 21 camera HAL1 blobs NEED libcamera_client.so, which A13 builds only for
# /system, so the camera provider failed to link and there were 0 cameras
# ("library \"libcamera_client.so\" not found: needed by
# /vendor/lib/libmtkcam_fwkutils.so", 2026-09-24).
PRODUCT_PACKAGES += \
    libcamera_client_vendor

# ---------------------------------------------------------------------------
# Vendor shims (shims/Android.bp).  Per-symbol evidence in the 18.1 documents
# VENDOR_A11_BLOB_AUDIT.md and los/device/meizu/m95/BLOB_SHIMS.md.
# ---------------------------------------------------------------------------
PRODUCT_PACKAGES += \
    libm95shim_gui \
    libm95shim_power \
    libm95shim_audioutils \
    libm95shim_ui \
    libm95shim_utils \
    libm95shim_sf \
    libm95shim_nparcel \
    libm95shim_net \
    libm95shim_netd_client \
    libm95shim_region \
    libm95shim_fs_mgr \
    libm95shim_skia \
    libm95shim_camera_client \
    libm95shim_media \
    libm95shim_mediautils \
    libm95shim_android_runtime \
    libm95shim_icuuc \
    libm95shim_icui18n \
    libm95shim_android \
    libm95shim_drmframework \
    libm95shim_stagefright \
    libm95shim_jnigraphics \
    libm95shim_btvendor \
    libm95shim_ssl \
    libm95shim_mnld \
    libm95shim_perfservice \
    libm95probe

# Flyme system libs (libsurfacetexture_bitmap*, libvfb/vmp_render.meizu) are
# absent from the blob tree (like the APKs) — re-add with the camera apps.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/configs/public.libraries-meizu.txt:$(TARGET_COPY_OUT_SYSTEM)/etc/public.libraries-meizu.txt

PRODUCT_DEVICE := m95

# This line LOSES and is meant to: lineage_m95.mk inherits
# product_launched_with_n_mr1.mk (25) after device.mk and the last inherit in
# the chain wins (measured on 18.1: get_build_var -> 25).  25 is the honest
# value for a Nougat-MR1 handset.  Kept because raising the effective level is
# a deliberate future step and this is where it would be done.
PRODUCT_SHIPPING_API_LEVEL := 30

# Dalvik heap — ~3 GB usable, AOSP 3072 profile (FACT, 16.0 tree: empty heap
# props starved system_server to 16 MB and killed WifiStateMachine).
PRODUCT_PROPERTY_OVERRIDES += \
    dalvik.vm.heapstartsize=8m \
    dalvik.vm.heapgrowthlimit=288m \
    dalvik.vm.heapsize=768m \
    dalvik.vm.heaptargetutilization=0.75 \
    dalvik.vm.heapminfree=512k \
    dalvik.vm.heapmaxfree=8m

# Dexpreopt: AOT-compile ("speed") the apps the owner touches first.
#
# FACT (build of 2026-09-16, compiler-filter in the odex headers of the target
# files): only SystemUI and TrebuchetQuickStep -- LineageOS's own speed list,
# out/soong/dexpreopt.config SpeedApps -- and the system-server apps came out
# "speed".  Everything else, the apps below included, is "verify": none of
# them ships a profile (dexpreopt_config/<app>_dexpreopt.config) and the
# fallback filter compiles no code (build/soong/dexpreopt/dexpreopt.go:403-413).
# Such an app runs interpreted + JIT, and the JIT code dies with the process,
# until the daily idle-and-charging bg-dexopt (pm.dexopt.bg-dexopt=
# speed-profile) has collected a profile and run -- so the first days after a
# flash are exactly when the keyboard, Settings and the dialer stutter.
# Cost: about 110 MB of /system (odex ~2.4x dex, calibrated on SystemUI:
# 12.6 MB dex -> 30.0 MB odex); the system image holds 1.8 GB today.
# Check after the build:
#   strings -n3 <app>/oat/arm64/<app>.odex | grep -A1 -x compiler-filter
PRODUCT_DEXPREOPT_SPEED_APPS += \
    Settings \
    LatinIME \
    Dialer \
    Contacts \
    messaging \
    Aperture \
    DocumentsUI \
    IntentResolver \
    PackageInstaller \
    TeleService

PRODUCT_AAPT_CONFIG := normal
PRODUCT_AAPT_PREF_CONFIG := xxhdpi

# ---------------------------------------------------------------------------
# Ramdisk: fstab (with /vendor on custom/mmcblk0p3), init, ueventd.
# The `subsystem graphics/input` ueventd blocks are load-bearing (FACT: black
# screen + dead touch without them, DEVICE_FACTS.md).
# ---------------------------------------------------------------------------
PRODUCT_PACKAGES += \
    fstab.mt6797 \
    fstab.mt6797.ramdisk \
    ueventd.mt6797.rc \
    ueventd.mt6797.ramdisk.rc \
    init.mt6797.rc \
    init.mt6797.usb.rc \
    init.m95.modem.rc \
    init.m95.connectivity.rc \
    init.m95.tee.rc \
    init.m95.thermal.rc \
    init.m95.cpuset.rc \
    init.m95.mem.rc \
    init.m95.sensors.rc \
    init.m95.volte.rc \
    goodixfpd.rc \
    init.m95.bootlog.rc \
    m95-cpuset.sh \
    m95-bdaddr.sh \
    m95-fatal-capture.sh

# VINTF device manifest (target-level 1: minimal framework requirements while
# N-era blobs are being adapted).
DEVICE_MANIFEST_FILE := $(LOCAL_PATH)/manifest.xml

# ---------------------------------------------------------------------------
# Treble HAL backbone.
#
# Every *-service below that is a defaultPassthroughServiceImplementation()
# needs its *-impl.so in /vendor/lib{,64}/hw, or it exits 1 five seconds after
# start, forever ("Could not get passthrough implementation").  Verify after
# every full build: installed-files-vendor.txt must list one -impl per
# passthrough service (18.1 shipped nine services without their impl once, and
# the ram-console census showed exactly those in a 5 s restart loop).
#
# Android 13 deltas vs the 18.1 list:
#   * drm@1.3-service.clearkey no longer exists; the clearkey plugin is
#     android.hardware.drm@1.4-service.clearkey.
#   * keymaster@3.0-impl/-service DO still exist (hardware/interfaces/
#     keymaster/3.0/default/Android.mk) and keystore2 can drive a legacy
#     Keymaster 3 through its km_compat layer, so the legacy path is kept
#     rather than switching to the software KeyMint.
# ---------------------------------------------------------------------------
PRODUCT_PACKAGES += \
    android.hardware.graphics.allocator@2.0-impl \
    android.hardware.graphics.allocator@2.0-service \
    android.hardware.graphics.composer@2.1-service \
    android.hardware.graphics.mapper@2.0-impl-2.1 \
    android.hardware.memtrack@1.0-impl \
    android.hardware.memtrack@1.0-service \
    android.hardware.renderscript@1.0-impl \
    android.hardware.health@2.1-impl \
    android.hardware.health@2.1-service \
    android.hardware.power@1.0-impl \
    android.hardware.power@1.0-service \
    android.hardware.light@2.0-impl \
    android.hardware.light@2.0-service \
    lights.mt6797 \
    android.hardware.vibrator@1.0-impl \
    android.hardware.vibrator@1.0-service \
    android.hardware.ir@1.0-impl \
    android.hardware.ir@1.0-service \
    libtinycompress \
    android.hardware.audio@2.0-impl \
    android.hardware.audio@2.0-service \
    android.hardware.audio.effect@2.0-impl \
    android.hardware.audio@6.0-impl \
    android.hardware.audio.effect@6.0-impl \
    audio.r_submix.default \
    audio.usb.default \
    android.hardware.keymaster@3.0-impl \
    android.hardware.keymaster@3.0-service \
    android.hardware.drm@1.0-impl \
    android.hardware.drm@1.0-service \
    android.hardware.drm@1.4-service.clearkey \
    android.hardware.gnss@1.0-impl \
    android.hardware.gnss@1.0-service \
    android.hardware.camera.provider@2.4-impl \
    android.hardware.camera.provider@2.4-service \
    android.hardware.sensors@1.0-impl \
    android.hardware.sensors@1.0-service \
    android.hardware.wifi@1.0-service \
    android.hardware.bluetooth@1.0-impl \
    android.hardware.bluetooth@1.0-service

# RAW16 for the rear camera and 4:3 viewfinder sizes for both:
# libm95_camera_metadata_raw appends the rows to the vendor's own stream tables
# (the copy AppStreamMgr::checkStream and the pipeline read).
# TARGET_LD_SHIM_LIBS in BoardConfig.mk loads it into the 32-bit provider, which
# cannot link without it -- do not drop it from here. Off switches without a
# reflash: persist.camera.raw=0 / preview_43=0 and a provider restart. See
# camera_metadata_raw/m95_scaler_raw.cpp.
PRODUCT_PACKAGES += \
    libm95_camera_metadata_raw

# Google Camera as the default camera (owner's request, 2026-09-25): MGC 8.9.097
# V25, the build that shoots best on this HAL (RAW16 from the row above), with
# the GServices shim it needs without GMS; overlay-gcam points the power-button
# gesture and the lockscreen shortcut at it. Aperture stays, for video and as the
# fallback. The APKs are not in git: run gcam/fetch-gcam.sh once per checkout;
# it leaves gcam/.fetched only after both hashes and all 25 libraries check out.
# This product does not set PRODUCT_ENFORCE_PACKAGES_EXIST, so a module missing
# from PRODUCT_PACKAGES would be dropped without a word (build/make/core/
# main.mk), hence the explicit check.
ifneq ($(M95_WITHOUT_GCAM),true)
  ifneq ($(words $(wildcard \
          $(LOCAL_PATH)/gcam/MGC_8.9.097_A11_V25_MGC.apk \
          $(LOCAL_PATH)/gcam/GcamServicesProvider-1.6.1-photos.apk \
          $(LOCAL_PATH)/gcam/.fetched)),3)
    $(error m95: Google Camera is not in $(LOCAL_PATH)/gcam; run $(LOCAL_PATH)/gcam/fetch-gcam.sh, or build with M95_WITHOUT_GCAM=true)
  endif
  PRODUCT_PACKAGES += \
      MGC_8_9_097 \
      GcamServicesProvider
  DEVICE_PACKAGE_OVERLAYS += $(LOCAL_PATH)/overlay-gcam
endif

# Gatekeeper: the AOSP SOFTWARE implementation instead of the MediaTek blob.
# The framework cannot live without an IGatekeeper (18.1, vendor17: with none
# registered LockSettingsService throws and system_server restarts every ~2
# min).  gatekeeper.mt6797.so imports the N-era libgatekeeper ABI, which
# neither R nor T provides, so the blob stays out until it has a shim.
# Credentials enrolled under another gatekeeper will not verify against this one
# (different HMAC key): expect to clear lock settings once.
PRODUCT_PACKAGES += \
    android.hardware.gatekeeper@1.0-service.software

# Fingerprint HAL — our own copy of the LineageOS @2.0 service, not the shared
# module (fingerprint/Android.bp explains why).  Both device fixes are 16.0 work
# proven on hardware: the blob's device structure is 272 bytes, not AOSP's 240,
# so an unpatched wrapper calls cancel where it means authenticate; and its
# enumerate slot is NULL.  The middle of the chain,
# /vendor/bin/goodixfingerprintd, is started by rootdir/goodixfpd.rc.
PRODUCT_PACKAGES += \
    android.hardware.biometrics.fingerprint@2.0-service.m95

# TFA98xx smart-amp DSP container (speaker firmware; 16.0 FACT: without it
# "tfa98xx_mute(): DSP not loaded(no FW: 3)" and the loudspeaker is dead).
# hals.conf: the sensors.mt6797 multi-HAL sub-HAL list; the blob dlopen()s those
# strings verbatim and fopen()s the file by the constant "/system/etc/hals.conf"
# — that string is rewritten in place to "/vendor/etc/hals.conf" (same length)
# by the blob patcher.  Without both halves "dumpsys sensorservice" prints
# "No Sensors on the device".  The file has no comment syntax.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/prebuilt/tfa98xx.cnt:$(TARGET_COPY_OUT_VENDOR)/firmware/tfa98xx.cnt \
    $(LOCAL_PATH)/prebuilt/hals.conf:$(TARGET_COPY_OUT_VENDOR)/etc/hals.conf

# ---------------------------------------------------------------------------
# Wi-Fi userspace (FACT config, 16.0 + 18.1)
# ---------------------------------------------------------------------------
PRODUCT_PACKAGES += \
    lib_driver_cmd_mt66xx \
    libwifi-hal-mt66xx \
    hostapd \
    wificond \
    wpa_supplicant \
    libwpa_client

PRODUCT_COPY_FILES += \
    external/wpa_supplicant_8/wpa_supplicant/wpa_supplicant_template.conf:$(TARGET_COPY_OUT_VENDOR)/etc/wifi/wpa_supplicant.conf

# ---------------------------------------------------------------------------
# FM radio (receive).  Worked on 16.0 (FACT 2026-08-14: node /dev/fm 226,0,
# /proc/fm -> "FM POWER OFF").  libfmjni is the MTK implementation over the
# ioctl node (jni/fmr/fmr.h: FM_DEV_NAME "/dev/fm") and builds as long as no
# BOARD_HAVE_QCOM_FM/BCM_FM/SLSI_FM is set.  The vendor half is already in the
# image: /vendor/lib{,64}/libfmcust.so plus the two mt6631 firmware blobs, which
# m95-vendor-extra.mk additionally copies to /system/etc/firmware/mt6631/
# because OUR kernel opens the DSP patch by absolute path with filp_open.
# ---------------------------------------------------------------------------
PRODUCT_PACKAGES += \
    FMRadio

# Key layouts (FACT names, live-verified /proc/bus/input/devices)
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/keylayout/ACCDET.kl:$(TARGET_COPY_OUT_VENDOR)/usr/keylayout/ACCDET.kl \
    $(LOCAL_PATH)/keylayout/fp-keys.kl:$(TARGET_COPY_OUT_VENDOR)/usr/keylayout/fp-keys.kl \
    $(LOCAL_PATH)/keylayout/mtk-kpd.kl:$(TARGET_COPY_OUT_VENDOR)/usr/keylayout/mtk-kpd.kl

# ---------------------------------------------------------------------------
# Hardware feature permissions (conservative set from the 16.0/18.1 trees)
#
# android.hardware.telephony.ims is a gate Pie did not have: PhoneGlobals
# constructs the ImsResolver ONLY when hasSystemFeature(FEATURE_TELEPHONY_IMS).
# ---------------------------------------------------------------------------
PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/handheld_core_hardware.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/handheld_core_hardware.xml \
    frameworks/native/data/etc/android.hardware.bluetooth.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.bluetooth.xml \
    frameworks/native/data/etc/android.hardware.bluetooth_le.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.bluetooth_le.xml \
    frameworks/native/data/etc/android.hardware.location.gps.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.location.gps.xml \
    frameworks/native/data/etc/android.hardware.telephony.gsm.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.telephony.gsm.xml \
    frameworks/native/data/etc/android.hardware.telephony.ims.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.telephony.ims.xml \
    frameworks/native/data/etc/android.hardware.camera.front.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.camera.front.xml \
    frameworks/native/data/etc/android.hardware.camera.flash-autofocus.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.camera.flash-autofocus.xml \
    frameworks/native/data/etc/android.hardware.sensor.accelerometer.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.sensor.accelerometer.xml \
    frameworks/native/data/etc/android.hardware.sensor.compass.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.sensor.compass.xml \
    frameworks/native/data/etc/android.hardware.sensor.gyroscope.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.sensor.gyroscope.xml \
    frameworks/native/data/etc/android.hardware.sensor.light.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.sensor.light.xml \
    frameworks/native/data/etc/android.hardware.sensor.proximity.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.sensor.proximity.xml \
    frameworks/native/data/etc/android.hardware.touchscreen.multitouch.jazzhand.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.touchscreen.multitouch.jazzhand.xml \
    frameworks/native/data/etc/android.hardware.usb.accessory.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.usb.accessory.xml \
    frameworks/native/data/etc/android.hardware.usb.host.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.usb.host.xml \
    frameworks/native/data/etc/android.hardware.fingerprint.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.fingerprint.xml \
    frameworks/native/data/etc/android.hardware.wifi.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.wifi.xml \
    frameworks/native/data/etc/android.hardware.wifi.direct.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.wifi.direct.xml \
    frameworks/native/data/etc/android.hardware.consumerir.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.consumerir.xml

# Privileged-permission allowlist for ForgeImsService (com.mediatek.ims,
# /system/priv-app, pulled in by vendor/forge/ims/forge-ims.mk from
# lineage_m95.mk).  Not optional: lineage-20 sets
# ro.control_privapp_permissions=enforce (vendor/lineage/config/common.mk:84),
# and on 18.1 the missing file made system_server throw "Signature|privileged
# permissions not in privapp-permissions whitelist: {com.mediatek.ims ...
# READ_PRECISE_PHONE_STATE}" and restart every ~19 s -- the phone never
# finished booting (FACT 2026-09-07).  It goes to /system, next to the APK.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/permissions/privapp-permissions-com.mediatek.ims.xml:$(TARGET_COPY_OUT_SYSTEM)/etc/permissions/privapp-permissions-com.mediatek.ims.xml

# ---------------------------------------------------------------------------
# Media configs.  Their absence was measured live on 18.1 (2026-09-07) and is a
# SINGLE packaging defect with four unrelated-looking symptoms: empty codec list
# ("IOmxStore reports parsing error"), no decoder, no encoder, and every camera
# app crashing with "Could not find supported video qualities".
#
# Two things differ from the 16.0 block, both read off the sources:
#  1) destination is vendor, not system — MediaCodecsXmlParser searches
#     /product/etc, /odm/etc, /vendor/etc, /system/etc in that order;
#  2) media_profiles.xml MUST be installed as media_profiles_V1_0.xml, because
#     MediaProfiles.cpp builds the name from ro.media.xml_variant.profiles whose
#     default is "_V1_0" and nothing here sets that property.
# The media_codecs_* files are pulled in by <Include href="..."/> relative to the
# same directory, which is why they all sit side by side.
# ---------------------------------------------------------------------------
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/media/media_profiles.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_profiles_V1_0.xml \
    $(LOCAL_PATH)/media/media_codecs.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_codecs.xml \
    $(LOCAL_PATH)/media/media_codecs_mediatek_audio.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_codecs_mediatek_audio.xml \
    $(LOCAL_PATH)/media/media_codecs_mediatek_video.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_codecs_mediatek_video.xml \
    $(LOCAL_PATH)/media/media_codecs_google_audio.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_codecs_google_audio.xml \
    $(LOCAL_PATH)/media/media_codecs_google_video_le.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_codecs_google_video_le.xml \
    $(LOCAL_PATH)/media/media_codecs_performance.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_codecs_performance.xml

# ---------------------------------------------------------------------------
# Audio policy configuration.  Android 10 removed the legacy audio_policy.conf
# parser and the vendor blob ships nothing else, so without this file
# AudioPolicyManager falls back to setDefault(): zero output devices, zero input
# devices, every stream Min 0 / Max 0, and AudioRecord::start returns -38.
# Measured on 18.1 before the file existed (2026-09-07).
# The file is converted from the stock Nougat vendor/etc/audio_policy.conf.
# ---------------------------------------------------------------------------
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/audio/audio_policy_configuration.xml:$(TARGET_COPY_OUT_VENDOR)/etc/audio_policy_configuration.xml

# The six xi:include targets of that file.  They must be COPIED, not listed in
# PRODUCT_PACKAGES: the prebuilt_etc modules of the same name exist in
# frameworks/av/services/audiopolicy/config/Android.bp but ninja does not know
# them in this configuration, so the entries would be dropped silently and the
# volume tables would never reach the image (libxml2: "failed to load external
# entity /vendor/etc/audio_policy_volumes.xml", every stream Min 0 / Max 0).
# xi:include resolves relative to the including file, so all six go next to it.
AUDIO_POLICY_CFG_DIR := frameworks/av/services/audiopolicy/config
PRODUCT_COPY_FILES += \
    $(AUDIO_POLICY_CFG_DIR)/a2dp_audio_policy_configuration.xml:$(TARGET_COPY_OUT_VENDOR)/etc/a2dp_audio_policy_configuration.xml \
    $(AUDIO_POLICY_CFG_DIR)/usb_audio_policy_configuration.xml:$(TARGET_COPY_OUT_VENDOR)/etc/usb_audio_policy_configuration.xml \
    $(AUDIO_POLICY_CFG_DIR)/r_submix_audio_policy_configuration.xml:$(TARGET_COPY_OUT_VENDOR)/etc/r_submix_audio_policy_configuration.xml \
    $(AUDIO_POLICY_CFG_DIR)/audio_policy_volumes.xml:$(TARGET_COPY_OUT_VENDOR)/etc/audio_policy_volumes.xml \
    $(AUDIO_POLICY_CFG_DIR)/default_volume_tables.xml:$(TARGET_COPY_OUT_VENDOR)/etc/default_volume_tables.xml \
    $(AUDIO_POLICY_CFG_DIR)/surround_sound_configuration_5_0.xml:$(TARGET_COPY_OUT_VENDOR)/etc/surround_sound_configuration_5_0.xml

# MTK omx *additional* vendor seccomp policy (16.0 device.mk, verbatim
# reasoning).  media.codec loads /system/etc/seccomp_policy/mediacodec.policy and
# then CONCATENATES the /vendor one onto it, so this is purely additive and is
# the supported way to widen the sandbox from a device tree.  Without it,
# creating any MTK video ENCODER component SIGSYSes media.codec on `sysinfo`.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/seccomp/mediacodec.policy:$(TARGET_COPY_OUT_VENDOR)/etc/seccomp_policy/mediacodec.policy

# Telephony props — VERBATIM stock Flyme 8.0.5.0A build.prop (FACT, 16.0).
PRODUCT_PROPERTY_OVERRIDES += \
    ril.first.md=1 \
    ril.external.md=0 \
    ril.telephony.mode=0 \
    mtk.eccci.c2k=enabled \
    ro.mtk_c2k_support=1 \
    ro.mtk_enable_md3=1 \
    rild.libpath=mtk-ril.so \
    wifi.interface=wlan0 \
    wifi.direct.interface=p2p0 \
    ro.telephony.sim.count=2 \
    persist.radio.multisim.config=dsds

# Bring-up: insecure ADB early. Remove once stable.
PRODUCT_DEFAULT_PROPERTY_OVERRIDES += \
    ro.secure=0 \
    ro.debuggable=1 \
    ro.adb.secure=0 \
    persist.sys.usb.config=adb

# ---------------------------------------------------------------------------
# DELIBERATELY NOT CARRIED OVER FROM 18.1 — do not "restore" without reading
# M95_LOS20_TREE.md first:
#
#  * (vendor/forge/ims -- ForgeImsService -- used to be listed here.  It is
#    carried over again, ported to API 33 in the forge_ims repo, branch
#    lineage-20: see lineage_m95.mk and the privapp-permissions block below.)
#
#  * (librilmtk used to be listed here.  It is carried over again: see the
#    PRODUCT_PACKAGES block next to librilimp and hardware/ril branch
#    meizu-legacy-vendor.)
#
#  * libcamera_client_vendor.  Same story: an 18.1-local vendor variant of a
#    frameworks/av library.  Android 13 does not ship one.  camera.mt6797.so
#    needs libcamera_client, so the camera HAL is expected to fail to load until
#    this is rebuilt.
#
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# VNDK-core libraries copied into /vendor for the sphal namespace.
#
# FACT 2026-09-09/10 (Android 13 GSI on this handset): the Mali blob
# vendor/lib64/egl/libGLES_mali.so has DT_NEEDED libbinder.so, and
# SurfaceFlinger — a SYSTEM process — dlopen()s it in the *sphal* namespace.
# Since Android 12 the sphal namespace is given LLNDK and VNDK-SP only, never
# VNDK-core, so the load fails:
#   E vndksupport: Could not load /vendor/lib64/egl/libGLES_mali.so from sphal
#     namespace: dlopen failed: library "libbinder.so" not found
# and libEGL aborts with "couldn't find an OpenGL ES implementation" before any
# UI exists.  libnetutils is the next one in the same chain (libGLES_mali ->
# ... -> libbwc.so), found immediately after libbinder was fixed.
# sphal searches /odm/${LIB} and /vendor/${LIB} only, so a vendor copy is both
# sufficient and isolated.
#
# This is NOT a GSI-only workaround: the rule that sphal gets no VNDK-core is a
# property of Android 12+ linkerconfig, so it applies to this native build too.
# The copies here are the v30 libraries produced by the 18.1 build of this same
# device (kept with the other blobs, outside git).
#
# 2026-09-24: the libbinder copies are GONE; libnetutils stays.  On the GSI the
# vendor ran VNDK v30, and there the v30 libbinder was consistent with the rest.
# This vendor is VNDK 33, and the copy broke every vendor process that needs
# libbinder (meizu-fleet/designs/M95_LINK_AUDIT_20260924.md):
#   * FACT: /vendor/lib{,64}/libbinder.so (sha256 4e76092e...) imports
#     thread_store_get/thread_store_set (JUMP_SLOT, BIND_NOW); only the v30
#     libcutils defines them, the v33 one does not (nm -D).
#   * FACT: the vendor default namespace searches /vendor/${LIB} before its
#     vndk link (linkerconfig vendordefault.cc; bionic find_library_internal),
#     so the copy was not sphal-only.  It failed to link in 19 of 41 modelled
#     boot processes: composer, allocator (libged), audio, camera,
#     vndservicemanager, and the Mali closure in SurfaceFlinger/zygote.
#   * FACT: A13-built vendor code needs libbinder symbols v30 lacks (5 for
#     libgui_vendor, 5 for vndservicemanager).
# Without the copy, vendor processes take libbinder from the VNDK v33 apex:
# clean in the model, N blobs included.  The sphal half moves to the platform:
# system/linkerconfig branch meizu-legacy-vendor (f132f5b,
# meizu-fleet/patches/system_linkerconfig/) adds libbinder.so to the
# sphal -> vndk link.  WITHOUT that patch, SurfaceFlinger still cannot load
# EGL ("libbinder.so" not found in sphal), exactly as on the GSI.
# libnetutils (v30) links cleanly against VNDK 33 in the same model.
PRODUCT_COPY_FILES += \
    vendor/meizu/m95/proprietary/vendor/lib64/libnetutils.so:$(TARGET_COPY_OUT_VENDOR)/lib64/libnetutils.so \
    vendor/meizu/m95/proprietary/vendor/lib/libnetutils.so:$(TARGET_COPY_OUT_VENDOR)/lib/libnetutils.so
# ---------------------------------------------------------------------------
