# libwifi-hal-mt66xx — SoC-agnostic MTK wifi HAL (from the m681/MT6755 port,
# via vendor/mediatek/wlan/wifi_hal in the LOS16 tree). R adaptation: header
# deps through libhardware_legacy_headers (the include-path-for helper used
# on LOS16 does not cover R's header-library layout).
LOCAL_PATH := $(call my-dir)

include $(CLEAR_VARS)

LOCAL_MODULE := libwifi-hal-mt66xx
LOCAL_PROPRIETARY_MODULE := true

LOCAL_CFLAGS += -Wno-unused-parameter -Wno-int-to-pointer-cast
LOCAL_CFLAGS += -Wno-maybe-uninitialized -Wno-parentheses
LOCAL_CPPFLAGS += -Wno-conversion-null

LOCAL_C_INCLUDES += \
    external/libnl/include \
    external/wpa_supplicant_8/src/drivers \
    hardware/libhardware_legacy/include/hardware_legacy

LOCAL_HEADER_LIBRARIES := libhardware_legacy_headers
LOCAL_HEADER_LIBRARIES += libutils_headers liblog_headers libcutils_headers

LOCAL_SRC_FILES := \
    wifi_hal.cpp \
    common.cpp \
    cpp_bindings.cpp \
    wifi_logger.cpp \
    wifi_offload.cpp

include $(BUILD_STATIC_LIBRARY)
