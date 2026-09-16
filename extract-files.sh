#!/bin/bash
#
# Copyright (C) 2016 The CyanogenMod Project
# Copyright (C) 2017-2026 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#
# extract-files.sh — Meizu MX6 (m95).
#
# The blob source for this port is NOT a live device: it is the stock
# Flyme 8.0.5.0A system image (Android 7.1.1 / NMF26O) unpacked with sdat2img,
# see meizu_mx6_m95/DEVICE_FACTS.md.  Run it as
#
#     ./extract-files.sh <path to the unpacked stock system tree>
#
# Two device-specific warnings that cost this port real time before:
#   * sdat2img turns symlinks into TEXT files.  After extracting, `file` every
#     blob; the ones known to be symlinks in stock (keystore/gatekeeper
#     .mt6797/.mz6797_6m_n, vendor/lib{,64}/hw/vulkan.mt6797.so) come out as
#     ASCII garbage.  vulkan is recreated as a real symlink by
#     vendor/meizu/m95/Android.mk; the others must be re-linked by hand.
#   * several shipped blobs are BYTE-PATCHED (sensors multi-HAL hals.conf path,
#     librilmtk soname rename, camera checkStream).  A fresh extract undoes
#     those patches.
#

set -e

DEVICE=m95
VENDOR=meizu

# Load extract_utils and do some sanity checks
MY_DIR="${BASH_SOURCE%/*}"
if [[ ! -d "${MY_DIR}" ]]; then MY_DIR="${PWD}"; fi

ANDROID_ROOT="${MY_DIR}/../../.."

HELPER="${ANDROID_ROOT}/tools/extract-utils/extract_utils.sh"
if [ ! -f "${HELPER}" ]; then
    echo "Unable to find helper script at ${HELPER}"
    exit 1
fi
source "${HELPER}"

# Default to sanitizing the vendor folder before extraction
CLEAN_VENDOR=true

ONLY_COMMON=
ONLY_FIRMWARE=
ONLY_TARGET=
KANG=
SECTION=

while [ "${#}" -gt 0 ]; do
    case "${1}" in
        --only-common)
            ONLY_COMMON=true
            ;;
        --only-firmware)
            ONLY_FIRMWARE=true
            ;;
        --only-target)
            ONLY_TARGET=true
            ;;
        -n | --no-cleanup)
            CLEAN_VENDOR=false
            ;;
        -k | --kang)
            KANG="--kang"
            ;;
        -s | --section)
            SECTION="${2}"
            shift
            CLEAN_VENDOR=false
            ;;
        *)
            SRC="${1}"
            ;;
    esac
    shift
done

if [ -z "${SRC}" ]; then
    SRC="adb"
fi

function blob_fixup() {
    case "${1}" in
        # No automatic fixups are declared here on purpose.  Every patched blob
        # in this port was patched with a named, reviewed script under
        # meizu_mx6_m95/tools/blobpatch/ and is documented in
        # vendor/meizu/m95/proprietary-files.txt.  Re-implementing them as
        # silent sed/patchelf one-liners here would hide them.
        *)
            ;;
    esac
}

# Initialize the helper
setup_vendor "${DEVICE}" "${VENDOR}" "${ANDROID_ROOT}" false "${CLEAN_VENDOR}"

extract "${MY_DIR}/proprietary-files.txt" "${SRC}" "${KANG}" --section "${SECTION}"

"${MY_DIR}/setup-makefiles.sh"
