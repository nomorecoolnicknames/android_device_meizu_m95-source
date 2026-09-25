#!/usr/bin/env python3
"""Box a Nougat android::Parcel that a stock MTK blob keeps by value, so it
stops overrunning the larger Android 13 Parcel.

WHY
---
Several MTK blobs in this port were compiled against Nougat, where
sizeof(android::Parcel) is 104 bytes on LP64 (and 88 on ILP32). On Android 13
Parcel grew (initState() now writes past the Nougat tail), so every blob that
keeps a Parcel as a *by-value* stack/heap local reserves too little room and the
A13 constructor overruns it:

  * /vendor/lib64/librilimp.so  -> rild SIGSEGV in ~Parcel/RefBase::decStrong
    (capture m95-b16-rild-crash-20260924);
  * /vendor/lib/libmal_rilproxy.so -> mtkmal SIGABRT "stack corruption detected
    (-fstack-protector)": the A13 Parcel ctor writes over the stack cookie of
    an ARM function (0x1a5ac; crash return 0x1acb0 = __stack_chk_fail), taking
    down the whole VoLTE MAL chain (capture m95-b18-volte-20260925).

WHAT
----
Two reproducible, reversible edits to the blob:

  1. .dynstr rename: every "android6Parcel" becomes "android6Pbrcel" (same
     length, 6Parcel -> 6Pbrcel). The blob then imports android::Pbrcel::*
     instead of android::Parcel::*, so those calls bind to libm95shim_nparcel
     (device/meizu/m95/shims/nparcel.cpp), which backs the blob's undersized
     box with a heap-allocated *real* Parcel. Only method symbols carry
     "android6Parcel"; nullParcelReleaseFunction (25nullParcel...) never does,
     so it is left alone. Works for ILP32 and LP64: the token is identical
     regardless of the size_t mangling (EPKhj vs EPKhm).

  2. patchelf --add-needed libm95shim_nparcel.so, so the box library is in the
     blob's namespace and Pbrcel resolves.

The shim treats the blob's box as opaque storage whose first pointer-sized word
holds the real Parcel*; nothing else in it is touched, so it never overflows.
See nparcel.cpp for the safety argument (no inline Parcel field access, no
Parcel object crossing the blob boundary).

Idempotent: re-running is a no-op. Keeps the pristine blob as <file>.orig (or
<file>.<sha256 prefix> if .orig already exists), matching tools/blobpatch
conventions in the 18.1 workspace.

Usage: box-nparcel.py /path/to/blob.so [more.so ...]
"""
import hashlib
import os
import re
import shutil
import struct
import subprocess
import sys

NEEDED = b"libm95shim_nparcel.so"
PATCHELF = os.path.expanduser("~/.local/bin/patchelf")

# Known pristine blobs (sha256 -> label). Unknown blobs still proceed if the
# .dynstr guards below hold, with a warning.
KNOWN = {
    "d3d8309e57861ec3946c56fe96535bc9c96aa838b57db4c4b2bdbed7a3550a47":
        "vendor/lib64/librilimp.so (64-bit, boxed 317fe586...)",
    "32f50d9be73e6cd6298c4f816c213d9f1560c53875fec36cf068b54352e81fe8":
        "vendor/lib/libmal_rilproxy.so (32-bit)",
}


def dynstr(data):
    """Return (offset, size) of .dynstr for a 32- or 64-bit little-endian ELF."""
    is64 = data[4] == 2
    if is64:
        e_shoff, = struct.unpack_from("<Q", data, 0x28)
        e_shentsize, e_shnum, e_shstrndx = struct.unpack_from("<HHH", data, 0x3A)
        name_at = lambda o: struct.unpack_from("<I", data, o)[0]
        str_at = lambda o: struct.unpack_from("<Q", data, o + 0x18)[0]  # sh_offset
        size_at = lambda o: struct.unpack_from("<Q", data, o + 0x20)[0]
        shstr_off_field = 0x18
    else:
        e_shoff, = struct.unpack_from("<I", data, 0x20)
        e_shentsize, e_shnum, e_shstrndx = struct.unpack_from("<HHH", data, 0x2E)
        name_at = lambda o: struct.unpack_from("<I", data, o)[0]
        str_at = lambda o: struct.unpack_from("<I", data, o + 0x10)[0]  # sh_offset
        size_at = lambda o: struct.unpack_from("<I", data, o + 0x14)[0]
        shstr_off_field = 0x10
    shstr_hdr = e_shoff + e_shstrndx * e_shentsize
    shstr_off = str_at(shstr_hdr) if is64 else struct.unpack_from(
        "<I", data, shstr_hdr + 0x10)[0]
    for i in range(e_shnum):
        o = e_shoff + i * e_shentsize
        n = name_at(o)
        end = data.index(b"\0", shstr_off + n)
        if data[shstr_off + n:end] == b".dynstr":
            return str_at(o), size_at(o)
    raise SystemExit("no .dynstr")


def backup(path):
    dst = path + ".orig"
    if os.path.exists(dst):
        pref = hashlib.sha256(open(path, "rb").read()).hexdigest()[:12]
        dst = path + "." + pref
        if os.path.exists(dst):
            return
    shutil.copy2(path, dst)
    print("  backup -> %s" % os.path.basename(dst))


def rename(path):
    data = bytearray(open(path, "rb").read())
    if data[:4] != b"\x7fELF":
        sys.exit("%s: not an ELF" % path)
    ds_off, ds_sz = dynstr(data)
    seg = bytes(data[ds_off:ds_off + ds_sz])

    n_par = seg.count(b"android6Parcel")
    n_box = seg.count(b"android6Pbrcel")
    if n_par == 0 and n_box > 0:
        print("  rename: already applied (%d Pbrcel strings)" % n_box)
        return False
    if n_par == 0:
        sys.exit("  rename: no android6Parcel strings and none boxed -- refusing")
    # Guard: nullParcelReleaseFunction, if present, has no "android6Parcel" and
    # is therefore untouched; assert it survives byte-for-byte.
    n_null = seg.count(b"nullParcelReleaseFunction")

    for m in re.finditer(rb"android6Parcel", bytes(data[ds_off:ds_off + ds_sz])):
        pos = ds_off + m.start() + len(b"android")
        assert bytes(data[pos:pos + 7]) == b"6Parcel"
        data[pos:pos + 7] = b"6Pbrcel"

    new_seg = bytes(data[ds_off:ds_off + ds_sz])
    if new_seg.count(b"nullParcelReleaseFunction") != n_null:
        sys.exit("  nullParcelReleaseFunction guard failed")
    open(path, "wb").write(data)
    print("  rename: %d android6Parcel -> android6Pbrcel in .dynstr" % n_par)
    return True


def add_needed(path):
    have = subprocess.run([PATCHELF, "--print-needed", path],
                          capture_output=True, text=True).stdout.split()
    if NEEDED.decode() in have:
        print("  add-needed: %s already present" % NEEDED.decode())
        return False
    subprocess.run([PATCHELF, "--add-needed", NEEDED.decode(), path], check=True)
    print("  add-needed: %s" % NEEDED.decode())
    return True


def box(path):
    print("%s:" % path)
    sha = hashlib.sha256(open(path, "rb").read()).hexdigest()
    if sha in KNOWN:
        print("  pristine: %s" % KNOWN[sha])
        backup(path)
    else:
        data = open(path, "rb").read()
        ds_off, ds_sz = dynstr(bytearray(data))
        if b"android6Pbrcel" not in data[ds_off:ds_off + ds_sz]:
            print("  WARNING: sha256 %s not in the known-pristine table and not "
                  "yet boxed; proceeding only because the .dynstr guards hold" % sha)
            backup(path)
    changed = rename(path)
    changed = add_needed(path) or changed
    new = hashlib.sha256(open(path, "rb").read()).hexdigest()
    print("  sha256 %s -> %s" % (sha, new))
    print("  %s" % ("changed" if changed else "no change (idempotent)"))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    for p in sys.argv[1:]:
        box(p)
