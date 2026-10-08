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

L_CFLAGS += \
    -DANDROID_P2P \
    -DCONFIG_ACS \
    -DCONFIG_ANDROID_LOG \
    -DCONFIG_AP \
    -DCONFIG_BACKEND_FILE \
    -DCONFIG_CTRL_IFACE \
    -DCONFIG_CTRL_IFACE_AIDL \
    -DCONFIG_CTRL_IFACE_UNIX \
    -DCONFIG_DPP \
    -DCONFIG_DPP2 \
    -DCONFIG_DRIVER_NL80211 \
    -DCONFIG_ECC \
    -DCONFIG_ERP \
    -DCONFIG_FILS \
    -DCONFIG_GAS \
    -DCONFIG_GAS_SERVER \
    -DCONFIG_AIDL \
    -DCONFIG_HMAC_SHA256_KDF \
    -DCONFIG_HMAC_SHA384_KDF \
    -DCONFIG_HMAC_SHA512_KDF \
    -DCONFIG_HS20 \
    -DCONFIG_IEEE80211AC \
    -DCONFIG_IEEE80211R \
    -DCONFIG_INTERWORKING \
    -DCONFIG_IPV6 \
    -DCONFIG_JSON \
    -DCONFIG_MBO \
    -DCONFIG_NO_ACCOUNTING \
    -DCONFIG_NO_RADIUS \
    -DCONFIG_NO_RADIUS \
    -DCONFIG_NO_RANDOM_POOL \
    -DCONFIG_NO_ROAMING \
    -DCONFIG_NO_VLAN \
    -DCONFIG_OFFCHANNEL \
    -DCONFIG_OWE \
    -DCONFIG_P2P \
    -DCONFIG_SAE \
    -DCONFIG_SAE_PK \
    -DCONFIG_SHA256 \
    -DCONFIG_SHA384 \
    -DCONFIG_SHA512 \
    -DCONFIG_SMARTCARD \
    -DCONFIG_SME \
    -DCONFIG_SUITEB \
    -DCONFIG_SUITEB192 \
    -DCONFIG_TDLS \
    -DCONFIG_WEP \
    -DCONFIG_WIFI_DISPLAY \
    -DCONFIG_WNM \
    -DCONFIG_WPS \
    -DCONFIG_WPS_ER \
    -DCONFIG_WPS_NFC \
    -DCONFIG_WPS_OOB \
    -DCONFIG_WPS_UPNP \
    -DEAP_AKA \
    -DEAP_AKA_PRIME \
    -DEAP_GTC \
    -DEAP_LEAP \
    -DEAP_MD5 \
    -DEAP_MSCHAPv2 \
    -DEAP_OTP \
    -DEAP_PEAP \
    -DEAP_PWD \
    -DEAP_SERVER \
    -DEAP_SERVER_IDENTITY \
    -DEAP_SERVER_WSC \
    -DEAP_SIM \
    -DEAP_TLS \
    -DEAP_TLS_OPENSSL \
    -DEAP_TTLS \
    -DEAP_WSC \
    -DIEEE8021X_EAPOL \
    -DNEED_AP_MLME \
    -DPKCS12_FUNCS \
    -DWPA_IGNORE_CONFIG_ERRORS \


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
