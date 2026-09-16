# lights.mt6797 built from source for m95 — see lights.c header for why the
# stock blob cannot work (red/green/blue/button-backlight nodes absent).
#
# On 18.1 this module is also what makes the light HAL exist at all:
# android.hardware.light@2.0-service is the AOSP passthrough service, its
# -impl does hw_get_module(LIGHTS_HARDWARE_MODULE_ID) -> lights.<ro.hardware>
# = lights.mt6797.so, and with no such library installed the service still
# registers ILight/default but reports no supported type, which is what the
# framework prints as "LightsService: Light requested not available on this
# device. <n>" (FACT 2026-09-07, vendor28: /proc/<light-hal>/maps carried the
# impl and nothing named lights*). The blob's PRODUCT_COPY_FILES entries are
# absent from vendor-18.1/meizu/m95/m95-vendor.mk and must stay absent: copy
# rules are emitted after module rules in this tree and would overwrite the
# module in the image (LOS16 lesson, tools/patches/
# m95-vendor-drop-lights-blob-copy.patch).
LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)
LOCAL_MODULE := lights.mt6797
LOCAL_MODULE_RELATIVE_PATH := hw
LOCAL_PROPRIETARY_MODULE := true
LOCAL_MODULE_TAGS := optional
LOCAL_SRC_FILES := lights.c
LOCAL_SHARED_LIBRARIES := liblog
LOCAL_HEADER_LIBRARIES := libhardware_headers
LOCAL_MULTILIB := both
LOCAL_CFLAGS := -Wall -Werror
include $(BUILD_SHARED_LIBRARY)
