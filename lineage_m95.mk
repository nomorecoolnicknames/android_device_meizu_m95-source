#
# Copyright (C) 2026 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#
# lineage_m95 — LineageOS 20 (Android 13, SDK 33) for Meizu MX6 (m95, MT6797).
# Full Treble, real /vendor partition on `custom` (mmcblk0p3), vendor built
# against VNDK 30.  Ported from the 18.1 tree that booted this device
# (meizu_mx6_m95/device-18.1/meizu/m95); see meizu-fleet/trees/M95_LOS20_TREE.md.
#

# Inherit 64-bit configs (zygote64_32: the Mali/camera/RIL blob closure has
# 32-bit-only libraries, so the 32-bit zygote is load-bearing here).
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base_telephony.mk)

# Inherit some common LineageOS stuff
$(call inherit-product, vendor/lineage/config/common_full_phone.mk)

# Inherit from m95 device
$(call inherit-product, device/meizu/m95/device.mk)

# Framework / lineage-sdk resource overlays.
DEVICE_PACKAGE_OVERLAYS += device/meizu/m95/overlay

# A-only legacy partition map, N-era blobs.  This sets PRODUCT_SHIPPING_API_LEVEL
# to 25, which is the honest value for a handset that shipped with Nougat MR1,
# and it is what relaxes part of the Treble requirements.  It MUST come after
# device.mk: the last inherit in the chain wins (measured on 18.1:
# `get_build_var PRODUCT_SHIPPING_API_LEVEL` -> 25).
$(call inherit-product, $(SRC_TARGET_DIR)/product/product_launched_with_n_mr1.mk)

# Device identifier. This must come after all inclusions
PRODUCT_DEVICE := m95
PRODUCT_NAME := lineage_m95
BOARD_VENDOR := meizu
PRODUCT_BRAND := Meizu
PRODUCT_MODEL := Meizu MX6
PRODUCT_MANUFACTURER := Meizu
TARGET_VENDOR := meizu

PRODUCT_GMS_CLIENTID_BASE := android-meizu

PRODUCT_BUILD_PROP_OVERRIDES += \
    PRIVATE_BUILD_DESC="m95-user 7.1.1 NMF26O 1623837408 release-keys"

# Set BUILD_FINGERPRINT variable to be picked up by both system and vendor build.prop
BUILD_FINGERPRINT := "Meizu/meizu_MX6/MX6:7.1.1/NMF26O/1623837408:user/release-keys"
