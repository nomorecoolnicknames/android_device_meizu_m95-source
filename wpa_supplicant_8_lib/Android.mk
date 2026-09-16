# forge duplicate device module guard for m2note
ifneq ($(TARGET_DEVICE),m2note)
#
# Copyright (C) 2008 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

LOCAL_PATH := $(call my-dir)

ifeq ($(WPA_SUPPLICANT_VERSION),VER_0_8_X)
    WPA_SUPPL_DIR = external/wpa_supplicant_8
    WPA_SRC_FILE :=

ifneq ($(BOARD_WPA_SUPPLICANT_DRIVER),)
    CONFIG_DRIVER_$(BOARD_WPA_SUPPLICANT_DRIVER) := y
endif
ifneq ($(BOARD_HOSTAPD_DRIVER),)
    CONFIG_DRIVER_$(BOARD_HOSTAPD_DRIVER) := y
endif

include $(WPA_SUPPL_DIR)/wpa_supplicant/android.config

# [FACT 2026-08-18, лейн log-audit] android.config включается только ради
# make-переменных; в define'ы компилятора его никто здесь не переводил, в
# отличие от wpa_supplicant/Android.mk:1471-1473 (там CONFIG_CTRL_IFACE_HIDL=y
# из android.config:343 становится -DCONFIG_HIDL -DCONFIG_CTRL_IFACE_HIDL).
# Этот файл разыменовывает wpa_s->conf, а в struct wpa_supplicant ПЕРЕД conf
# лежит член hidl_object_key под #ifdef CONFIG_CTRL_IFACE_HIDL
# (wpa_supplicant_i.h:510-512). Без define'а раскладка библиотеки короче на
# 8 байт: lib читала offset 0xd8 (confanother, в Android всегда NULL), тогда
# как в бинаре conf лежит на 0xe0. Доказано objdump'ом собранных объектов:
#   mediatek_driver_cmd_nl80211.o:      ldr x8, [x23, #216]   (0xd8)
#   wpa_supplicant_reload_configuration: ldr x8, [x19, #224]  (0xe0)
# Следствие: КАЖДАЯ driver_cmd (SETSUSPENDMODE, COUNTRY, MACADDR, RXFILTER,
# BTCOEX...) умирала на «wpa_s->conf is NULL. Exiting» — страна регдомена не
# ставилась, suspend-оптимизации и rx-фильтры не включались. Зеркалим define
# бинаря; из членов до conf у нас затрагивается только этот (MATCH_IFACE и
# DBUS выключены в обеих сборках).
ifdef CONFIG_CTRL_IFACE_HIDL
L_CFLAGS += -DCONFIG_HIDL -DCONFIG_CTRL_IFACE_HIDL
endif

WPA_SUPPL_DIR_INCLUDE = $(WPA_SUPPL_DIR)/src \
	$(WPA_SUPPL_DIR)/src/common \
	$(WPA_SUPPL_DIR)/src/drivers \
	$(WPA_SUPPL_DIR)/src/l2_packet \
	$(WPA_SUPPL_DIR)/src/utils \
	$(WPA_SUPPL_DIR)/src/wps \
	$(WPA_SUPPL_DIR)/wpa_supplicant

ifdef CONFIG_DRIVER_NL80211
WPA_SUPPL_DIR_INCLUDE += external/libnl/include
WPA_SRC_FILE += mediatek_driver_cmd_nl80211.c
endif

ifdef CONFIG_DRIVER_WEXT
#error doesn't support CONFIG_DRIVER_WEXT
endif

# To force sizeof(enum) = 4
ifeq ($(TARGET_ARCH),arm)
L_CFLAGS += -mabi=aapcs-linux
endif

ifdef CONFIG_ANDROID_LOG
L_CFLAGS += -DCONFIG_ANDROID_LOG
endif

########################

include $(CLEAR_VARS)
LOCAL_MODULE := lib_driver_cmd_mt66xx
# Vendor module: R builds wpa_supplicant/hostapd as vendor executables, and a
# platform static lib cannot link into them under Treble (BOARD_VNDK_VERSION).
LOCAL_PROPRIETARY_MODULE := true
# R builds wpa_supplicant/hostapd with CFI (external/wpa_supplicant_8 is in the
# CFI include paths); an uninstrumented static driver_cmd lib linked into them
# fails the icall check as soon as StaIface::getMacAddressInternal calls
# driver_cmd (vendor25: wpa_supplicant SIGABRT __cfi_check_fail x3, no wlan0).
LOCAL_SANITIZE := cfi
LOCAL_SHARED_LIBRARIES := libc libcutils
LOCAL_CFLAGS := $(L_CFLAGS)
LOCAL_SRC_FILES := $(WPA_SRC_FILE)
LOCAL_C_INCLUDES := $(WPA_SUPPL_DIR_INCLUDE)
include $(BUILD_STATIC_LIBRARY)

########################

endif
endif # forge duplicate device module guard for m2note
