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

PRODUCT_SOONG_NAMESPACES += \
    device/meizu/m95 \
    vendor/meizu/m95

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

# A-GPS: the stock profile list with the default SUPL server switched from
# supl.qxwz.com (TLS refused) to supl.google.com; same first-entry-wins rule.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/configs/agps_profiles_conf2.xml:$(TARGET_COPY_OUT_VENDOR)/etc/agps_profiles_conf2.xml

# ---------------------------------------------------------------------------
# Vendor blobs (real /vendor image on the `custom` partition)
# ---------------------------------------------------------------------------
$(call inherit-product, vendor/meizu/m95/m95-vendor.mk)
$(call inherit-product, vendor/meizu/m95/m95-vendor-extra.mk)

# Vendor prebuilt modules (vendor/meizu/m95/Android.mk).
PRODUCT_PACKAGES += \
    vulkan.mt6797_symlinks \
    librilimp

PRODUCT_PACKAGES += \
    librilmtk

PRODUCT_PACKAGES += \
    libstdc++.vendor

PRODUCT_PACKAGES += \
    libgui_vendor \
    libsensor_vendor \
    libgui_m95 \
    libsensor_m95

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

PRODUCT_PROPERTY_OVERRIDES += \
    dalvik.vm.heapstartsize=8m \
    dalvik.vm.heapgrowthlimit=288m \
    dalvik.vm.heapsize=768m \
    dalvik.vm.heaptargetutilization=0.75 \
    dalvik.vm.heapminfree=512k \
    dalvik.vm.heapmaxfree=8m

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
    init.m95.powertrap.rc \
    init.m95.mem.rc \
    init.m95.sensors.rc \
    init.m95.volte.rc \
    goodixfpd.rc \
    m95-cpuset.sh \
    m95-perfprofile.sh \
    m95-powertrap.sh \
    m95-bdaddr.sh

# BCB auto-return guard for TEST images (rootdir/m95-bcbguard.sh,
# init.m95.bcbguard.rc, WORKAROUNDS.md D5): armed at `on init`, cleared 300 s
# after boot_completed, so a crash in between lands in TWRP instead of a boot
# loop. Never in the everyday image -- a power loss during boot would leave the
# owner in TWRP. Build with M95_TEST_BCBGUARD=true.
ifeq ($(M95_TEST_BCBGUARD),true)
PRODUCT_PACKAGES += \
    init.m95.bcbguard.rc \
    m95-bcbguard.sh
endif

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
    android.hardware.thermal@2.0-service.m95 \
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

# VoLTE log filter (shims/volte_log.c, TARGET_LD_SHIM_LIBS in BoardConfig.mk,
# WORKAROUNDS.md P10). Off by default: build with M95_VOLTE_LOGFILTER=true.
ifeq ($(M95_VOLTE_LOGFILTER),true)
PRODUCT_PACKAGES += \
    libm95volte_logfilter
endif

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

PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/prebuilt/tfa98xx.cnt:$(TARGET_COPY_OUT_VENDOR)/firmware/tfa98xx.cnt \
    $(LOCAL_PATH)/prebuilt/hals.conf:$(TARGET_COPY_OUT_VENDOR)/etc/hals.conf

PRODUCT_PACKAGES += \
    lib_driver_cmd_mt66xx \
    libwifi-hal-mt66xx \
    hostapd \
    wificond \
    wpa_supplicant \
    libwpa_client

# Hotspot: ap0 as a tetherable Wi-Fi interface, no randomized AP BSSID
# (rro_overlays/*/res/values/config.xml say why).
PRODUCT_PACKAGES += \
    M95TetheringConfigOverlay \
    M95WifiOverlay

PRODUCT_COPY_FILES += \
    external/wpa_supplicant_8/wpa_supplicant/wpa_supplicant_template.conf:$(TARGET_COPY_OUT_VENDOR)/etc/wifi/wpa_supplicant.conf

PRODUCT_PACKAGES += \
    FMRadio

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

PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/permissions/privapp-permissions-com.mediatek.ims.xml:$(TARGET_COPY_OUT_SYSTEM)/etc/permissions/privapp-permissions-com.mediatek.ims.xml

PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/media/media_profiles.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_profiles_V1_0.xml \
    $(LOCAL_PATH)/media/media_codecs.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_codecs.xml \
    $(LOCAL_PATH)/media/media_codecs_mediatek_audio.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_codecs_mediatek_audio.xml \
    $(LOCAL_PATH)/media/media_codecs_mediatek_video.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_codecs_mediatek_video.xml \
    $(LOCAL_PATH)/media/media_codecs_google_audio.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_codecs_google_audio.xml \
    $(LOCAL_PATH)/media/media_codecs_google_video_le.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_codecs_google_video_le.xml \
    $(LOCAL_PATH)/media/media_codecs_performance.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_codecs_performance.xml

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

M95_ADB_KEYS ?=
ifneq ($(M95_ADB_KEYS),)
ifeq ($(wildcard $(M95_ADB_KEYS)),)
$(warning m95: M95_ADB_KEYS=$(M95_ADB_KEYS) does not exist -- no /adb_keys, every computer will be asked for on the screen)
else
PRODUCT_ADB_KEYS := $(M95_ADB_KEYS)
endif
endif

M95_INSECURE_ADB ?= false
ifeq ($(M95_INSECURE_ADB),true)
PRODUCT_DEFAULT_PROPERTY_OVERRIDES += \
    ro.secure=0 \
    ro.debuggable=1 \
    ro.adb.secure=0
endif

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

PRODUCT_COPY_FILES += \
    vendor/meizu/m95/proprietary/vendor/lib64/libnetutils.so:$(TARGET_COPY_OUT_VENDOR)/lib64/libnetutils.so \
    vendor/meizu/m95/proprietary/vendor/lib/libnetutils.so:$(TARGET_COPY_OUT_VENDOR)/lib/libnetutils.so
# ---------------------------------------------------------------------------
