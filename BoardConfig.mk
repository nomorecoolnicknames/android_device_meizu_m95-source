#
# BoardConfig.mk — Meizu MX6 (m95, MT6797) on LineageOS 20 (Android 13, SDK 33).
#
# Provenance of every non-obvious value is recorded in
# meizu-fleet/trees/M95_LOS20_TREE.md (FACT / INFERENCE / HYPOTHESIS per
# <original-workspace>/CLAUDE.md §2).  Short form:
#   * boot geometry, partition table, panel, input names  -> DEVICE_FACTS.md
#     (byte-for-byte vs the stock boot.img / stock scatter / live device);
#   * Treble + real /vendor on `custom` (mmcblk0p3)       -> the LOS 18.1 tree
#     device-18.1/meizu/m95 that actually booted this device;
#   * VNDK 30                                            -> the vendor image
#     this port already ships (ro.vndk.version=30) and under which the
#     Android 13 GSI reached the launcher on this handset (2026-09-11).
#
# SPDX-License-Identifier: Apache-2.0
#

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

# Android 11+ запрещает ELF-файлы в PRODUCT_COPY_FILES и требует объявлять их
# модулями Soong (cc_prebuilt_binary / cc_prebuilt_library_shared). У нас 50
# таких блобов эпохи Nougat (autokd, batterywarning, aal, akmd09912 и др.) —
# первая полная сборка 2026-09-16 упала именно на этом гейте (build-m95.log).
#
# ТЕХНИЧЕСКИЙ ДОЛГ, а не решение: флаг лишь снимает проверку. Правильный путь —
# сгенерировать модули через extract-files.sh/setup-makefiles.sh. Пока блобы не
# конвертированы, никто не проверяет их DT_NEEDED — отсутствующая зависимость
# всплывёт только на устройстве, как «library not found» в logcat.
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

# ---------------------------------------------------------------------------
# Kernel — PREBUILT, never rebuilt from this tree.
# ---------------------------------------------------------------------------
# prebuilt/Image.gz-dtb is kernel/m685 @ 78e751a9 build #145
# ("Linux version 3.18.22-eng-g78e751a9-dirty ... #145 SMP PREEMPT Sun Sep 13
# 02:43:46 MSK 2026"), sha256
# b84b732d3d0e9dbb13d3a3e6e75d0fdae69e2c628cc31be048dfa881d824da7e, copied from
# the LOS 18.1 build tree
# nx549j/rom-nx549j-lineage-18.1-tissot/out/target/product/m95/obj/KERNEL_OBJ/
# arch/arm64/boot/Image.gz-dtb.  It is the kernel that carries the eBPF
# backport, the FFS-AIO backport and the dm-bufio/mnt fixes Android 13 needs.
# kernel/meizu/m95 deliberately does not exist in this tree, so
# vendor/lineage/build/tasks/kernel.mk takes the prebuilt branch
# (it prints a "using prebuilt kernel" warning — expected).
TARGET_PREBUILT_KERNEL := $(DEVICE_PATH)/prebuilt/Image.gz-dtb
TARGET_KERNEL_ARCH := arm64
TARGET_KERNEL_HEADER_ARCH := arm64
TARGET_KERNEL_VERSION := 3.18
BOARD_KERNEL_IMAGE_NAME := Image.gz-dtb

# Исходник ядра всё-таки нужен, хоть мы и шьём прибилт: модуль Soong
# generated_kernel_includes (vendor/lineage/build/soong/Android.bp:21) гонит
# "make -C $(TARGET_KERNEL_SOURCE) headers_install", и без исходника сборка
# падает на .dummy_dep с "kernel/meizu/m95: No such file or directory"
# (первая полная сборка 2026-09-16, build-m95.log).
#
# kernel/meizu/m95 — симлинк на <original-workspace>/meizu_mx6_m95/kernel/m685,
# Linux 3.18.22. Это ТО ЖЕ дерево, из которого собран наш прибилт (#145,
# sha256 b84b732d…24da7e), поэтому сгенерированные заголовки соответствуют
# ABI прошиваемого ядра — штатное предупреждение kernel.mk:186 про возможное
# расхождение к нашему случаю не относится.
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

# ---------------------------------------------------------------------------
# Partitions — A-only, no slots, no dynamic partitions.
# ---------------------------------------------------------------------------
# Sizes below come from the stock GPT
# (captures/a11-20260909/device-session/gpt/gpt-m95-before-20260911.bin,
# parsed: recovery 30 MiB, custom 512 MiB, boot 16 MiB, cache 432 MiB)
# EXCEPT `system`, which was grown from 2560 MiB to 4 GiB with sgdisk on
# 2026-09-11 (FLYME13_KERNEL_PLAN.md §10, HANDOFF_20260911_BPF_AUDIO_NET.md §0).
# The post-resize GPT was never captured, so 4294967296 is the documented size,
# not a measured one — verify with `sgdisk -p /dev/block/mmcblk0` from TWRP
# before trusting a full-size image.
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

# BOARD_VNDK_VERSION := 30 was TRIED FIRST and REJECTED — measured, not assumed.
# The vendor image this port ships today declares ro.vndk.version=30, so pinning
# the board to the v30 snapshot looked like the obvious match.  Two hard walls,
# both reproduced with `m nothing` on 2026-09-16 (log kept in
# meizu-fleet/trees/M95_LOS20_TREE.md §4):
#
#   1. Every vendor APEX in hardware/interfaces (power, sensors@2.1, usb@1.0,
#      vibrator, thermal@2.0) stops soong_build.  An apex takes the image
#      variant vendor.$(BOARD_VNDK_VERSION) (build/soong/apex/apex.go:673) while
#      an AOSP "vendor: true" cc module takes vendor.$(PLATFORM_VNDK_VERSION)
#      (build/soong/cc/image.go:515-533 — hardware/interfaces is in soong's
#      defaultDirectoryIncludedMap, i.e. it is NOT a vendor-proprietary path).
#      30 != 33, so the apex can never find its own binaries.
#   2. With the apexes hidden, soong then fails with
#      `"libc" depends on undefined module "vendor_snapshot"`
#      (build/soong/cc/cc.go:2144): any module with a vendor.30 image variant
#      demands a checked-in *vendor snapshot* module, which only exists in trees
#      that ship prebuilts/vendor/v30.  We build the vendor from source.
#
#   And even if both were papered over, the result would be an incoherent
#   /vendor: our device-tree modules compiled against VNDK 30, but every AOSP
#   HAL implementation we install (audio@6.0-impl, camera.provider@2.4-impl,
#   mapper@2.1, composer@2.1-service, ...) compiled against VNDK 33 and then
#   run in a v30 namespace — forward-incompatible by construction.
#
# So the vendor is built against the platform VNDK, exactly as the 18.1 tree
# did: 18.1 also said BOARD_VNDK_VERSION := current, and on Android 11 "current"
# simply WAS 30.  The 30-ness of that vendor was never a pin, it was the
# platform of the day.
BOARD_VNDK_VERSION := current

# The v30 VNDK apex is still shipped in the system image — see
# PRODUCT_EXTRA_VNDK_VERSIONS in device.mk.  That is what makes it possible to
# boot this system with the existing 18.1-built vendor.img (ro.vndk.version=30)
# for an A/B comparison, and it is the same thing the Android 13 GSI does
# (build/make/target/product/gsi_release.mk:66), which is the configuration in
# which this handset reached the launcher on 2026-09-11.

# NOTE: BOARD_VNDK_RUNTIME_DISABLE (VNDK-lite), which 18.1 used for bring-up, is
# a KATI_obsolete_var in Android 13 (build/make/core/config.mk:156) — VNDK-lite
# no longer exists.  Anything that relied on a vendor process seeing
# /system/lib must now be solved with a vendor-side copy of the library, the
# way libbinder/libnetutils are in device.mk.

# HIDL/VINTF device manifest
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
# The MT6797 gen3 driver rejects SIOCSIFHWADDR and the default wifi HAL would
# leave wlan0 DOWN after the failed MAC change (Android 13 asks for one on every
# enable/connect) -> no scan, no association.  FACT 2026-09-12.
WIFI_AVOID_IFACE_RESET_MAC_CHANGE := true

# Bluetooth — MTK combo chip (stock /dev/stpbt).
BOARD_HAVE_BLUETOOTH := true

# Dual SIM (FACT, 16.0 tree: SIM_COUNT=2 required for slot2 + 4-arg RIL env).
SIM_COUNT := 2

# N-era MTK RIL blob: libril must send the 8th setupDataCall string.
BOARD_USES_MTK_HARDWARE := true

# MTK gralloc0+fb module wrapped by the mapper@2.1 Gralloc0Hal adapter; the MTK
# vendor usage bit 26 must be accepted (FACT, 16.0 camera fix).
TARGET_ADDITIONAL_GRALLOC_10_USAGE_BITS ?= 0
TARGET_ADDITIONAL_GRALLOC_10_USAGE_BITS += | (1 << 26)

TARGET_OTA_ASSERT_DEVICE := m95,M95,m685,MX6,mx6

# Vendor blobs (real /vendor image).
include vendor/meizu/m95/BoardConfigVendor.mk
