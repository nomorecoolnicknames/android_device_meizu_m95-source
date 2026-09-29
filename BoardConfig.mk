# SPDX-License-Identifier: Apache-2.0
# BoardConfig.mk — Meizu MX6 (m95, MT6797) on LineageOS 20 (Android 13, SDK 33).

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
# УСТАРЕЛО (2026-09-16): раньше здесь стояло «kernel/meizu/m95 намеренно
# отсутствует, поэтому kernel.mk берёт ветку прибилта». Это больше не так —
# исходник пришлось подключить ради generated_kernel_includes (см. ниже),
# а ветка прибилта теперь удерживается флагом TARGET_FORCE_PREBUILT_KERNEL.
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

# НЕ ДОБАВЛЯТЬ СЮДА TARGET_KERNEL_ADDITIONAL_FLAGS ради headers_install —
# проверено 2026-09-16, до Soong оно не доходит:
#   * KERNEL_MAKE_FLAGS собирается в vendor/lineage/config/BoardConfigKernel.mk
#     (строка 105 обнуляет, 108-226 наполняют) и тут же уходит в Soong через
#     BoardConfigSoong.mk (EXPORT_TO_SOONG, снимок по `:=`);
#   * а TARGET_KERNEL_ADDITIONAL_FLAGS читается только в
#     vendor/lineage/build/tasks/kernel.mk:271 — это фаза make, уже ПОСЛЕ
#     экспорта, поэтому на genrule generated_kernel_includes не влияет.
# Проверять так: python3 -c по out/soong/soong.variables, ключ
# VendorVars.lineageVarsPlugin.KERNEL_MAKE_FLAGS.
#
# Настоящая причина падения headers_install была в самом ядре: 3.18 линкует
# однофайловые хост-программы (scripts/basic/fixdep) правилом host-csingle,
# которое, в отличие от соседних host-cmulti/host-cxxmulti, не передавало
# $(HOSTLDFLAGS) — поэтому переданный Lineage флаг -fuse-ld=lld до линковки не
# доезжал, а GNU ld в песочнице отсутствует намеренно (kernel.mk:264).
# Исправлено в дереве ядра: m685 commit 3522613e.

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

# Производительность: погасить самые дорогие отладочные механизмы ядра, не
# пересобирая его (подробно — meizu-fleet/trees/M95_PREFLASH_PERF.md §1).
#
# FACT: прибилт #145 собран из lineage_m95_defconfig, унаследованного от
# отладочного mx6_defconfig Meizu: MT_ENG_BUILD, PROVE_LOCKING, SLUB_DEBUG_ON,
# DMA_API_DEBUG, MTK_FTRACE_DEFAULT_ENABLE (.config той же сборки, KERNEL_OBJ
# 18.1, Image.gz-dtb sha256 b84b732d…).  Стоковое user-ядро Flyme ничего из
# этого не содержит: в его Image нет ни строк lockdep, ни DMA-API, ни проверок
# SLUB.  Вдобавок LK сам ставит в начало cmdline `slub_debug=O`, что на нашем
# ядре значит полную отладку SLUB (F/Z/P/U, снятие стека на каждый kmalloc и
# kfree, медленный путь аллокатора) почти для всех кэшей (mm/slub.c:1205,1224).
# Наши параметры идут ПОСЛЕ префикса LK (captures/m95-boot-b13-20260807/
# dmesg-first-b13.txt:57), поэтому побеждают:
#   slub_debug=-             отладка SLUB выключена целиком (mm/slub.c:1228-1229);
#   lockdep.prove_locking=0  без проверки графа зависимостей на каждом захвате
#                            блокировки (kernel/locking/lockdep.c:61-62, 3115);
#   dma_debug=off            без учёта каждого dma_map_* и без предвыделения
#                            таблицы записей (lib/dma-debug.c:997, 1027-1037);
#   trace_buf_size=1M        MTK на late_initcall включает ftrace и растит буфер
#                            до 4 МБ на КАЖДЫЙ CPU (kernel/trace/trace.c:340-341,
#                            mtk_trace.c:248-267), т.е. 40 МБ ОЗУ при 10 ядрах;
#                            запись всё равно гасит atrace.rc на late-init.
# Все четыре только выключают диагностику, поведение драйверов не меняется.
# Откат — удалить строку.  Проверка на аппарате: /proc/cmdline;
# /sys/module/lockdep/parameters/prove_locking = 0; в dmesg «DMA-API: debugging
# disabled on kernel command line»; /sys/kernel/slab/kmalloc-64/red_zone = 0;
# /sys/kernel/debug/tracing/buffer_size_kb = 1024.
BOARD_KERNEL_CMDLINE += slub_debug=- lockdep.prove_locking=0 dma_debug=off trace_buf_size=1M

# MX6 uses its board-specific A-only partition map; do not substitute another MTK board geometry.
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
# way libnetutils is in device.mk.  NOT for a VNDK library the vendor namespace
# also uses: a /vendor copy shadows the VNDK apex one in EVERY vendor process
# (libbinder, device.mk, 2026-09-24).

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
# The MT6797 gen3 driver rejects SIOCSIFHWADDR and the default wifi HAL would
# leave wlan0 DOWN after the failed MAC change (Android 13 asks for one on every
# enable/connect) -> no scan, no association.  FACT 2026-09-12.
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

# ---------------------------------------------------------------------------
# SELinux: neverallow-проверки ВКЛЮЧЕНЫ (2026-09-24, SELinux-лейн)
# ---------------------------------------------------------------------------
# До этого здесь стоял SELINUX_IGNORE_NEVERALLOWS := true с «четырьмя»
# нарушениями. Хостовый прогон того же конвейера (m4 -> checkpolicy ->
# version_policy -> secilc, бинарник байт-в-байт равен precompiled_sepolicy
# сборки 16.09) показал больше: secilc -- 11 neverallow (включая 54 правила
# enforce_sysprop_owner), эмуляция sepolicy_neverallows_vendor (вариант
# user) -- 196. Все сняты в sepolicy/vendor (свойства через
# vendor_*_prop и переразметку, goodixfpd, и т.д.), разбор --
# meizu-fleet/designs/M95_SEPOLICY_LOS20_20260924.md.
#
# На хосте проверено: secilc без -N rc=0; sepolicy_neverallows_vendor
# (checkpolicy) rc=0; sepolicy_tests.py rc=0; treble_sepolicy_tests
# CoredomainViolations/ViolatorAttributes/CoreDatatypeViolations rc=0
# (--fake-treble, т.к. PRODUCT_FULL_TREBLE_OVERRIDE := true); checkfc по
# file/property/vndservice_contexts OK.
# НЕ проверено на хосте: treble_sepolicy_tests TrebleCompatMapping (нужны
# старые плат-политики 28..32), sepolicy-analyze и sepolicy_compat_test.
# Если сборка упадёт именно на них -- вернуть строку ниже этим же коммитом
# (git revert), а не глушить отдельные правила.
# SELINUX_IGNORE_NEVERALLOWS := true

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
