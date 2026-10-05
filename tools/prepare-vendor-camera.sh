#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
tool_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
android_root="$(cd -- "${tool_dir}/../../../.." && pwd)"
python3 "${tool_dir}/camera-looper-compat.py" \
    --abi vndk33-looper136 \
    --file "${android_root}/vendor/meizu/m95/proprietary/vendor/lib/libmtkcam_sysutils.so" \
    "$@"
