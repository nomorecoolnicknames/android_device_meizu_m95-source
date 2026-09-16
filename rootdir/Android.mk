LOCAL_PATH := $(call my-dir)

# Init scripts -> /vendor/etc/init/hw (auto-imported by init second stage)
include $(CLEAR_VARS)
LOCAL_MODULE       := init.mt6797.rc
LOCAL_MODULE_TAGS  := optional
LOCAL_MODULE_CLASS := ETC
LOCAL_SRC_FILES    := init.mt6797.rc
LOCAL_MODULE_PATH  := $(TARGET_OUT_VENDOR_ETC)/init/hw
include $(BUILD_PREBUILT)

include $(CLEAR_VARS)
LOCAL_MODULE       := init.mt6797.usb.rc
LOCAL_MODULE_TAGS  := optional
LOCAL_MODULE_CLASS := ETC
LOCAL_SRC_FILES    := init.mt6797.usb.rc
LOCAL_MODULE_PATH  := $(TARGET_OUT_VENDOR_ETC)/init/hw
include $(BUILD_PREBUILT)

# MTK subsystem imports (binaries + full service set land in phase 2 with
# blobs; the rc files are harmless without their binaries: unknown services
# are only started on triggers that reference existing files).
include $(CLEAR_VARS)
LOCAL_MODULE       := init.m95.modem.rc
LOCAL_MODULE_TAGS  := optional
LOCAL_MODULE_CLASS := ETC
LOCAL_SRC_FILES    := init.m95.modem.rc
LOCAL_MODULE_PATH  := $(TARGET_OUT_VENDOR_ETC)/init/hw
include $(BUILD_PREBUILT)

include $(CLEAR_VARS)
LOCAL_MODULE       := init.m95.connectivity.rc
LOCAL_MODULE_TAGS  := optional
LOCAL_MODULE_CLASS := ETC
LOCAL_SRC_FILES    := init.m95.connectivity.rc
LOCAL_MODULE_PATH  := $(TARGET_OUT_VENDOR_ETC)/init/hw
include $(BUILD_PREBUILT)

include $(CLEAR_VARS)
LOCAL_MODULE       := init.m95.tee.rc
LOCAL_MODULE_TAGS  := optional
LOCAL_MODULE_CLASS := ETC
LOCAL_SRC_FILES    := init.m95.tee.rc
LOCAL_MODULE_PATH  := $(TARGET_OUT_VENDOR_ETC)/init/hw
include $(BUILD_PREBUILT)

include $(CLEAR_VARS)
LOCAL_MODULE       := init.m95.thermal.rc
LOCAL_MODULE_TAGS  := optional
LOCAL_MODULE_CLASS := ETC
LOCAL_SRC_FILES    := init.m95.thermal.rc
LOCAL_MODULE_PATH  := $(TARGET_OUT_VENDOR_ETC)/init/hw
include $(BUILD_PREBUILT)

include $(CLEAR_VARS)
LOCAL_MODULE       := init.m95.bootlog.rc
LOCAL_MODULE_TAGS  := optional
LOCAL_MODULE_CLASS := ETC
LOCAL_SRC_FILES    := init.m95.bootlog.rc
LOCAL_MODULE_PATH  := $(TARGET_OUT_VENDOR_ETC)/init/hw
include $(BUILD_PREBUILT)

include $(CLEAR_VARS)
LOCAL_MODULE       := init.m95.volte.rc
LOCAL_MODULE_TAGS  := optional
LOCAL_MODULE_CLASS := ETC
LOCAL_SRC_FILES    := init.m95.volte.rc
LOCAL_MODULE_PATH  := $(TARGET_OUT_VENDOR_ETC)/init/hw
include $(BUILD_PREBUILT)

include $(CLEAR_VARS)
LOCAL_MODULE       := goodixfpd.rc
LOCAL_MODULE_TAGS  := optional
LOCAL_MODULE_CLASS := ETC
LOCAL_SRC_FILES    := goodixfpd.rc
LOCAL_MODULE_PATH  := $(TARGET_OUT_VENDOR_ETC)/init/hw
include $(BUILD_PREBUILT)

include $(CLEAR_VARS)
LOCAL_MODULE       := init.m95.cpuset.rc
LOCAL_MODULE_TAGS  := optional
LOCAL_MODULE_CLASS := ETC
LOCAL_SRC_FILES    := init.m95.cpuset.rc
LOCAL_MODULE_PATH  := $(TARGET_OUT_VENDOR_ETC)/init/hw
include $(BUILD_PREBUILT)

include $(CLEAR_VARS)
LOCAL_MODULE       := init.m95.mem.rc
LOCAL_MODULE_TAGS  := optional
LOCAL_MODULE_CLASS := ETC
LOCAL_SRC_FILES    := init.m95.mem.rc
LOCAL_MODULE_PATH  := $(TARGET_OUT_VENDOR_ETC)/init/hw
include $(BUILD_PREBUILT)


# fstab -> /vendor/etc (fs_mgr + recovery reference) ...
# ... and the mount points its NV entries need in the system-image root
# (on R the root after switch_root is system.img, read-only: the mkdir lines
# in init.mt6797.rc `on fs` cannot create them, mount_all then fails those
# entries and init never sets ro.crypto.state -> zygote never starts).
include $(CLEAR_VARS)
LOCAL_MODULE       := fstab.mt6797
LOCAL_MODULE_TAGS  := optional
LOCAL_MODULE_CLASS := ETC
LOCAL_SRC_FILES    := fstab.mt6797
LOCAL_MODULE_PATH  := $(TARGET_OUT_VENDOR_ETC)
LOCAL_POST_INSTALL_CMD := mkdir -p $(TARGET_ROOT_OUT)/nvdata $(TARGET_ROOT_OUT)/nvcfg $(TARGET_ROOT_OUT)/protect_f $(TARGET_ROOT_OUT)/protect_s
include $(BUILD_PREBUILT)

# ... and first-stage ramdisk root (ReadDefaultFstab fallback: our 3.18
# kernel has no firmware/android/fstab DT node, so without this copy
# first-stage mount is skipped and /system never mounts).
# NOTE: TARGET_RAMDISK_OUT (out/.../ramdisk) is the boot-ramdisk staging that
# mkbootfs packs; TARGET_ROOT_OUT content does NOT reach boot.img on R.
include $(CLEAR_VARS)
LOCAL_MODULE       := fstab.mt6797.ramdisk
LOCAL_MODULE_STEM  := fstab.mt6797
LOCAL_MODULE_TAGS  := optional
LOCAL_MODULE_CLASS := ETC
LOCAL_SRC_FILES    := fstab.mt6797
LOCAL_MODULE_PATH  := $(TARGET_RAMDISK_OUT)
include $(BUILD_PREBUILT)

# ueventd rules for the boot ramdisk. R second-stage ueventd parses the
# ramdisk /ueventd.rc; without it there are no /dev/graphics + /dev/input
# nodes (black screen / dead touch — the proven LOS16 lesson). The /vendor
# copy (below) serves late-boot; the ramdisk copy serves first stage.
include $(CLEAR_VARS)
LOCAL_MODULE       := ueventd.mt6797.ramdisk.rc
LOCAL_MODULE_STEM  := ueventd.rc
LOCAL_MODULE_TAGS  := optional
LOCAL_MODULE_CLASS := ETC
LOCAL_SRC_FILES    := ueventd.mt6797.rc
LOCAL_MODULE_PATH  := $(TARGET_RAMDISK_OUT)
include $(BUILD_PREBUILT)

# ueventd rules -> /vendor (the subsystem graphics/input blocks are
# load-bearing: black screen + dead touch without them).
include $(CLEAR_VARS)
LOCAL_MODULE       := ueventd.mt6797.rc
LOCAL_MODULE_STEM  := ueventd.rc
LOCAL_MODULE_TAGS  := optional
LOCAL_MODULE_CLASS := ETC
LOCAL_SRC_FILES    := ueventd.mt6797.rc
LOCAL_MODULE_PATH  := $(TARGET_OUT_VENDOR)
include $(BUILD_PREBUILT)

# Helper scripts -> /vendor/bin
include $(CLEAR_VARS)
LOCAL_MODULE       := m95-cpuset.sh
LOCAL_MODULE_TAGS  := optional
LOCAL_MODULE_CLASS := ETC
LOCAL_SRC_FILES    := m95-cpuset.sh
LOCAL_MODULE_PATH  := $(TARGET_OUT_VENDOR_EXECUTABLES)
include $(BUILD_PREBUILT)

include $(CLEAR_VARS)
LOCAL_MODULE       := m95-bdaddr.sh
LOCAL_MODULE_TAGS  := optional
LOCAL_MODULE_CLASS := ETC
LOCAL_SRC_FILES    := m95-bdaddr.sh
LOCAL_MODULE_PATH  := $(TARGET_OUT_VENDOR_EXECUTABLES)
include $(BUILD_PREBUILT)

include $(CLEAR_VARS)
LOCAL_MODULE       := m95-fatal-capture.sh
LOCAL_MODULE_TAGS  := optional
LOCAL_MODULE_CLASS := ETC
LOCAL_SRC_FILES    := m95-fatal-capture.sh
LOCAL_MODULE_PATH  := $(TARGET_OUT_VENDOR_EXECUTABLES)
include $(BUILD_PREBUILT)
