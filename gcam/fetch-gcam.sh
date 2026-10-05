#!/bin/bash

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SRC=${1:?Pass the directory containing the separately supplied camera APKs}

CAMERA_APK=MGC_8.9.097_A11_V25_MGC.apk
CAMERA_SHA256=b5d196a4201398dafc5a1b01b233ec7cbde9d32c51e8b7848a9535ad4dc163e8
SERVICES_APK=GcamServicesProvider-1.6.1-photos.apk
SERVICES_SHA256=9b526fbd11e77ecc1ece496eb89a79d42fd1339e61aba54a5a201cd5f8a6510b

# The 25 libraries of MGC 8.9.097 V25, all arm64-v8a; it ships no 32-bit ones.
CAMERA_LIBS=25

fetch() {
    local name=$1 sum=$2
    if ! echo "$sum  $SRC/$name" | sha256sum --check --quiet --strict; then
        echo "fetch-gcam: $SRC/$name is missing or is not the pinned build" >&2
        exit 1
    fi
    # Already here (the source is this directory, or an earlier run linked it):
    # ln and cp would both refuse to copy a file onto itself.
    if [ ! "$SRC/$name" -ef "$HERE/$name" ]; then
        # A hard link where the source shares the filesystem: the APKs never
        # change, and the camera alone is 300 MB.
        ln -f "$SRC/$name" "$HERE/$name" 2>/dev/null || cp -f "$SRC/$name" "$HERE/$name"
    fi
    echo "$sum  $HERE/$name" | sha256sum --check --quiet --strict
}

# device.mk builds only with this stamp present, and it is written last.
rm -f "$HERE/.fetched"

fetch "$CAMERA_APK" "$CAMERA_SHA256"
fetch "$SERVICES_APK" "$SERVICES_SHA256"

mkdir -p "$HERE/lib/arm64"
rm -f "$HERE"/lib/arm64/*.so
unzip -q -j -o "$HERE/$CAMERA_APK" 'lib/arm64-v8a/*.so' -d "$HERE/lib/arm64"

found=$(find "$HERE/lib/arm64" -maxdepth 1 -name '*.so' | wc -l)
if [ "$found" -ne "$CAMERA_LIBS" ]; then
    echo "fetch-gcam: unpacked $found libraries, expected $CAMERA_LIBS" >&2
    exit 1
fi

printf '%s  %s\n%s  %s\n' "$CAMERA_SHA256" "$CAMERA_APK" \
    "$SERVICES_SHA256" "$SERVICES_APK" > "$HERE/.fetched"
echo "fetch-gcam: $CAMERA_APK, $SERVICES_APK and $found libraries in $HERE"
