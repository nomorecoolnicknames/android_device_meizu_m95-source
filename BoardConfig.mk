# SPDX-License-Identifier: Apache-2.0

DEVICE_PATH := device/meizu/m95

# Duplicate install rules (our N blobs vs AOSP default HAL modules at the same
# /vendor path, e.g. fingerprint.default) warn instead of erroring — carried
# over from 18.1.  The winner per path MUST be verified by md5 against the blob
# after each full build.
BUILD_BROKEN_DUP_RULES := true

# The N-era blobs are copied with PRODUCT_COPY_FILES, so nothing validates their
# DT_NEEDED closure; the few prebuilt *modules* we do declare need the ELF check
# relaxed for the same reason (see vendor/meizu/m95/Android.mk).
BUILD_BROKEN_MISSING_REQUIRED_MODULES := true

BUILD_BROKEN_ELF_PREBUILT_PRODUCT_COPY_FILES := true

# ---------------------------------------------------------------------------
# Architecture
# ---------------------------------------------------------------------------
# MT6797 = 2x Cortex-A72 + 4x Cortex-A53 + 4x Cortex-A53, ARMv8.0-A.
# NO ARMv8.1 / ARMv8.2 flags and no cortex-a55/a75/a76 cpu variant: this core
# has no LSE atomics, and any inline LSE instruction outside the runtime-
# dispatched __aarch64_* outline helpers is SIGILL on this device (FACT,
# established by the GSI lane of this project).
# `generic` is normalised to the empty string by Soong
# (build/soong/android/arch.go:1781), i.e. plain -march=armv8-a.
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-a
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_ABI2 :=
TARGET_CPU_VARIANT := generic

TARGET_2ND_ARCH := arm
TARGET_2ND_ARCH_VARIANT := armv8-a
TARGET_2ND_CPU_ABI := armeabi-v7a
TARGET_2ND_CPU_ABI2 := armeabi
TARGET_2ND_CPU_VARIANT := cortex-a53
TARGET_USES_64_BIT_BINDER := true

# ---------------------------------------------------------------------------
# Platform
# ---------------------------------------------------------------------------
TARGET_BOARD_PLATFORM := mt6797
TARGET_NO_BOOTLOADER := true
BOARD_VENDOR := meizu

TARGET_PREBUILT_KERNEL := $(DEVICE_PATH)/prebuilt/Image.gz-dtb
TARGET_KERNEL_ARCH := arm64
TARGET_KERNEL_HEADER_ARCH := arm64
TARGET_KERNEL_VERSION := 3.18
BOARD_KERNEL_IMAGE_NAME := Image.gz-dtb

TARGET_KERNEL_SOURCE := kernel/meizu/m95
TARGET_KERNEL_CONFIG := lineage_m95_defconfig


# Исходник есть и конфиг задан, поэтому без этого флага kernel.mk:192 полез бы
# собирать ядро из исходников. Нам нужен именно прибилт: ветка kernel.mk:180-190
# даёт FULL_KERNEL_BUILD := false и KERNEL_BIN := $(TARGET_PREBUILT_KERNEL).
TARGET_FORCE_PREBUILT_KERNEL := true

# Boot image geometry — FACT, parsed byte-for-byte out of the stock boot.img
# (DEVICE_FACTS.md).  Plain ANDROID! image, header v0, no MTK 512-byte header.
BOARD_KERNEL_BASE := 0x40078000
BOARD_KERNEL_OFFSET := 0x00008000
BOARD_RAMDISK_OFFSET := 0x04f88000
BOARD_KERNEL_TAGS_OFFSET := 0x03f88000
BOARD_SECOND_OFFSET := 0x00e88000
BOARD_KERNEL_PAGESIZE := 2048
BOARD_BOOT_HEADER_VERSION := 0
BOARD_KERNEL_CMDLINE := bootopt=64S3,32N2,64N2 androidboot.hardware=mt6797
BOARD_MKBOOTIMG_ARGS := --kernel_offset $(BOARD_KERNEL_OFFSET) \
    --ramdisk_offset $(BOARD_RAMDISK_OFFSET) \
    --second_offset $(BOARD_SECOND_OFFSET) \
    --tags_offset $(BOARD_KERNEL_TAGS_OFFSET) \
    --header_version $(BOARD_BOOT_HEADER_VERSION)

# First bring-up permissive, exactly as 16.0 and 18.1 started.  Enforcing comes
# after a denial census, not before the first boot.
BOARD_KERNEL_CMDLINE += androidboot.selinux=permissive

BOARD_KERNEL_CMDLINE += slub_debug=- lockdep.prove_locking=0 dma_debug=off trace_buf_size=1M

BOARD_BOOTIMAGE_PARTITION_SIZE := 16777216
BOARD_RECOVERYIMAGE_PARTITION_SIZE := 31457280
BOARD_SYSTEMIMAGE_PARTITION_SIZE := 4294967296
BOARD_CACHEIMAGE_PARTITION_SIZE := 452984832
BOARD_VENDORIMAGE_PARTITION_SIZE := 536870912
BOARD_FLASH_BLOCK_SIZE := 131072
AB_OTA_UPDATER := false

# /vendor is a REAL partition: the `custom` partition, mmcblk0p3, 512 MiB
# (FACT, GPT above + measured on device).  Not system/vendor.
TARGET_COPY_OUT_VENDOR := vendor
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := ext4

# A-only legacy layout: real recovery partition, no system-as-root rebuild.
BOARD_BUILD_SYSTEM_ROOT_IMAGE := false
BOARD_USES_RECOVERY_AS_BOOT := false
TARGET_NO_RECOVERY := false

# File systems — userdata is f2fs on this unit (FACT, live-verified).
BOARD_HAS_LARGE_FILESYSTEM := true
TARGET_USERIMAGES_USE_EXT4 := true
TARGET_USERIMAGES_USE_F2FS := true
BOARD_SYSTEMIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_CACHEIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_USERDATAIMAGE_FILE_SYSTEM_TYPE := f2fs

# Recovery
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/rootdir/fstab.mt6797
TARGET_RECOVERY_PIXEL_FORMAT := "RGBX_8888"
BOARD_HAS_NO_SELECT_BUTTON := true

# ---------------------------------------------------------------------------
# Display — 1080x1920 FT8716/Sharp.  The kernel does the 180-degree rotation in
# hardware (CONFIG_MTK_LCM_PHYSICAL_ROTATION="180"); adding a userspace rotation
# flips the UI upside down (FACT, observed on the glass).
# ---------------------------------------------------------------------------
TARGET_SCREEN_WIDTH := 1080
TARGET_SCREEN_HEIGHT := 1920
TARGET_SCREEN_DENSITY := 480

# ---------------------------------------------------------------------------
# Treble + VNDK 30
# ---------------------------------------------------------------------------
# PRODUCT_SHIPPING_API_LEVEL is 25 (product_launched_with_n_mr1.mk), which is
# below the 26 that would turn Treble on by itself, so it is forced here — the
# same switch the 18.1 tree used.
PRODUCT_FULL_TREBLE_OVERRIDE := true

BOARD_VNDK_VERSION := current



# HIDL/VINTF device manifest (target-level 3, see the history at its top).
DEVICE_MANIFEST_FILE := $(DEVICE_PATH)/manifest.xml

# Properties (split: system vs vendor partition)
TARGET_SYSTEM_PROP += $(DEVICE_PATH)/system.prop
TARGET_VENDOR_PROP += $(DEVICE_PATH)/vendor.prop

# SELinux — vendor policy only; BOARD_SEPOLICY_VERS deliberately left at the
# platform default (33.0).  18.1 proved that pinning it to an older version
# buys a paper check and costs a broken CIL mapping build.
BOARD_VENDOR_SEPOLICY_DIRS += $(DEVICE_PATH)/sepolicy/vendor

# ---------------------------------------------------------------------------
# Wi-Fi — MTK WMT/conn_soc stack (FACT: working config on 16.0 and 18.1).
# ---------------------------------------------------------------------------
BOARD_WLAN_DEVICE := MediaTek
WPA_SUPPLICANT_VERSION := VER_0_8_X
BOARD_WPA_SUPPLICANT_DRIVER := NL80211
BOARD_WPA_SUPPLICANT_PRIVATE_LIB := lib_driver_cmd_mt66xx
BOARD_HOSTAPD_DRIVER := NL80211
BOARD_HOSTAPD_PRIVATE_LIB := lib_driver_cmd_mt66xx
WIFI_DRIVER_STATE_CTRL_PARAM := /dev/wmtWifi
WIFI_DRIVER_STATE_ON := 1
WIFI_DRIVER_STATE_OFF := 0
# Hotspot. The wifi HAL switches chip mode (STA+P2P <-> AP) through
# DriverTool::ChangeFirmwareMode, which writes these strings to
# WIFI_DRIVER_FW_PATH_PARAM; left unset, the switch is a silent no-op
# (frameworks/opt/net/wifi/libwifi_hal/driver_tool.cpp:50-54) and hostapd is
# handed wlan0 with the driver still in STA mode. The WMT char device acts on
# the first letter: 'A' puts the gen3 driver in AP mode and registers ap0,
# 'S'/'P' return to STA mode and register p2p0 (kernel conn_soc
# wmt_chrdev_wifi.c:444-545, wlan/gen3 gl_p2p_init.c:30). Never set on 16.0 or
# 18.1 either. The AP interface name is ro.vendor.wifi.sap.interface.
WIFI_DRIVER_FW_PATH_PARAM := /dev/wmtWifi
WIFI_DRIVER_FW_PATH_STA := STA
WIFI_DRIVER_FW_PATH_AP := AP
WIFI_DRIVER_FW_PATH_P2P := P2P
WIFI_AVOID_IFACE_RESET_MAC_CHANGE := true

# Bluetooth — MTK combo chip (stock /dev/stpbt).
BOARD_HAVE_BLUETOOTH := true

# Dual SIM (FACT, 16.0 tree: SIM_COUNT=2 required for slot2 + 4-arg RIL env).
SIM_COUNT := 2

# N-era MTK RIL blob hosted by the AOSP rild.  BOARD_USES_MTK_LEGACY_RIL is
# the switch hardware/ril (branch meizu-legacy-vendor) reads on lineage-20: it
# builds librilmtk (our libril under the soname mtk-ril.so needs, librilimp in
# DT_NEEDED), links rild against it and compiles the MTK paths with
# -DMTK_HARDWARE (the 8th setupDataCall string, the seven-member RIL_Env,
# per-channel serialisation, the rild-mal server, ...).  On 18.1 the same
# switch was BOARD_USES_MTK_HARDWARE; on lineage-20 m2note and m5s set that one
# too and have no librilimp module, so hardware/ril no longer reads it.
BOARD_USES_MTK_HARDWARE := true
BOARD_USES_MTK_LEGACY_RIL := true
# Upstream hardware/ril ignores the flag and links rild against plain libril,
# which builds fine and then cannot load mtk-ril.so.  PRODUCT_PACKAGES does not
# catch that on this product (build/make/core/main.mk checks it only with
# PRODUCT_ENFORCE_PACKAGES_EXIST, and BUILD_BROKEN_MISSING_REQUIRED_MODULES is
# set above), so check for the branch itself.
ifeq ($(wildcard hardware/ril/libril/librilmtk_force_needed.c),)
$(error m95: hardware/ril is not on branch meizu-legacy-vendor (no libril/librilmtk_force_needed.c); rild would be built without librilmtk)
endif

# MTK gralloc0+fb module wrapped by the mapper@2.1 Gralloc0Hal adapter; the MTK
# vendor usage bit 26 must be accepted (FACT, 16.0 camera fix).
TARGET_ADDITIONAL_GRALLOC_10_USAGE_BITS ?= 0
TARGET_ADDITIONAL_GRALLOC_10_USAGE_BITS += | (1 << 26)

TARGET_OTA_ASSERT_DEVICE := m95,M95,m685,MX6,mx6

# Vendor blobs (real /vendor image).
include vendor/meizu/m95/BoardConfigVendor.mk


# Camera RAW16: libm95_camera_metadata_raw must be global in the camera provider
# before MediaTek's metadata store asks dlsym(RTLD_DEFAULT) for the IMX386 stream
# table (camera_metadata_raw/m95_scaler_raw.cpp). A shim of the executable is
# loaded with it, RTLD_GLOBAL, ahead of its DT_NEEDED
# (bionic/linker/linker_main.cpp:450-484), and unlike LD_PRELOAD it is not
# discarded under AT_SECURE. The provider gets AT_SECURE: it runs as cameraserver
# with `capabilities SYS_NICE`, and this 3.18 kernel still marks any non-root exec
# with a non-empty permitted set secure (kernel/m685 security/commoncap.c:653-656);
# under enforcing the init -> hal_camera_default transition would set it anyway.
# If the library is missing from the image the provider cannot link at all --
# keep it in PRODUCT_PACKAGES (device.mk).
TARGET_LD_SHIM_LIBS += \
    /vendor/bin/hw/android.hardware.camera.provider@2.4-service|/vendor/lib/libm95_camera_metadata_raw.so

TARGET_LD_SHIM_LIBS += \
    /vendor/bin/spm_loader|liblog.so

ifeq ($(M95_VOLTE_LOGFILTER),true)
TARGET_LD_SHIM_LIBS += \
    /vendor/bin/volte_stack|/vendor/lib/libm95volte_logfilter.so \
    /vendor/bin/volte_ua|/vendor/lib/libm95volte_logfilter.so \
    /vendor/bin/volte_imcb|/vendor/lib/libm95volte_logfilter.so
endif
