#
# Google Camera as the MX6's default camera: BSG's MGC 8.9.097 V25 and the
# GServices shim it cannot start without on a phone with no GMS, preinstalled
# on /product. Neither APK is in git; fetch-gcam.sh puts them here, checked
# against pinned sha256, together with the camera's unpacked JNI libraries.
# device.mk refuses to build without them unless M95_WITHOUT_GCAM=true.
#
# Both APKs are installed byte for byte (LOCAL_REPLACE_PREBUILT_APK_INSTALLED).
# The camera is signed with the v3 scheme alone (apksigner verify: v1 false,
# v2 false, v3 true), which covers the whole archive and leaves no JAR
# signature to fall back on. The ordinary prebuilt path would store its
# compressed .so entries uncompressed (uncompress-prebuilt-embedded-jni-libs)
# and, being PRESIGNED, not sign the result again -- an APK the package manager
# refuses. Keeping the signature has
# a second use: a copy the owner installed from the same file becomes an update
# of this one on the first boot, settings and all, instead of being removed as
# a signature mismatch.
#
# The camera's libraries are compressed inside the APK, and the package manager
# does not extract native code for a preinstalled app; it looks for it in
# <app>/lib/<arch>. So they are installed there as separate files, arm64 only,
# the one ABI the APK carries.
#
# No dexpreopt: 50 MB of dex would become an odex of several times that on
# /system, and the background dexopt job compiles the app on the device.
# The <uses-library> check is off because the manifest names ten optional
# com.google.android.camera* libraries that do not exist here.
#

LOCAL_PATH := $(call my-dir)

ifneq ($(wildcard $(LOCAL_PATH)/MGC_8.9.097_A11_V25_MGC.apk),)

include $(CLEAR_VARS)
LOCAL_MODULE := MGC_8_9_097
LOCAL_MODULE_CLASS := APPS
LOCAL_MODULE_SUFFIX := $(COMMON_ANDROID_PACKAGE_SUFFIX)
LOCAL_SRC_FILES := MGC_8.9.097_A11_V25_MGC.apk
LOCAL_REPLACE_PREBUILT_APK_INSTALLED := $(LOCAL_PATH)/$(LOCAL_SRC_FILES)
LOCAL_CERTIFICATE := PRESIGNED
LOCAL_PRODUCT_MODULE := true
LOCAL_MULTILIB := 64
LOCAL_PREBUILT_JNI_LIBS := \
    $(patsubst $(LOCAL_PATH)/%,%,$(wildcard $(LOCAL_PATH)/lib/arm64/*.so))
LOCAL_DEX_PREOPT := false
LOCAL_ENFORCE_USES_LIBRARIES := false
include $(BUILD_PREBUILT)

endif

# Lukas Pieper's Gcam Services Provider in its Google Photos flavour: it answers
# the READ_GSERVICES lookup GMS would, and it takes the review intent the camera
# fires when its thumbnail is tapped and hands the picture to the gallery. That
# second half is why this flavour and not the basic one -- the owner's phone
# runs it (build 18: com.google.android.apps.photos/
# de.lukaspieper.gcam.PreviewRedirectActivity after each shot). It takes the
# package name of Google Photos, which this build does not ship.
ifneq ($(wildcard $(LOCAL_PATH)/GcamServicesProvider-1.6.1-photos.apk),)

include $(CLEAR_VARS)
LOCAL_MODULE := GcamServicesProvider
LOCAL_MODULE_CLASS := APPS
LOCAL_MODULE_SUFFIX := $(COMMON_ANDROID_PACKAGE_SUFFIX)
LOCAL_SRC_FILES := GcamServicesProvider-1.6.1-photos.apk
LOCAL_REPLACE_PREBUILT_APK_INSTALLED := $(LOCAL_PATH)/$(LOCAL_SRC_FILES)
LOCAL_CERTIFICATE := PRESIGNED
LOCAL_PRODUCT_MODULE := true
LOCAL_DEX_PREOPT := false
LOCAL_ENFORCE_USES_LIBRARIES := false
include $(BUILD_PREBUILT)

endif
