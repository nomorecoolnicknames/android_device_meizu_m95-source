#!/usr/bin/env python3
"""Box librilimp's Nougat android::Parcel so it stops overrunning A13 storage.

WHY
---
/vendor/lib64/librilimp.so is the stock MTK 64-bit libril with its DT_SONAME
rewritten (tools/patches/librilmtk-rename-soname.py in the 18.1 workspace). It
was compiled against Nougat, where sizeof(android::Parcel) on LP64 is 104. On
Android 13 it is 120 and Parcel::initState() writes a 64-bit zero at object
offset 112. librilimp keeps Parcels as by-value stack/heap locals with exactly
104 bytes reserved (9 stack functions, 3 heap operator new(104)); the A13 ctor
overruns them and ~Parcel() then decStrong()s garbage -> rild SIGSEGV every ~5 s
once ForgeImsService connects (FACT, meizu-fleet capture
m95-b16-rild-crash-20260924: RefBase::decStrong <- librilimp
IMS_RIL_onUnsolicitedResponseSocket+1032).

WHAT
----
Two reproducible, reversible edits to librilimp.so:

  1. .dynstr rename: the 19 imported android::Parcel method strings become
     android::Pbrcel (6Parcel -> 6Pbrcel, identical length). librilimp then
     imports android::Pbrcel::* instead of android::Parcel::*, so those calls
     bind to libm95shim_nparcel (device/meizu/m95/shims/nparcel.cpp), which
     backs each 104-byte box with a heap-allocated real Parcel. Only the 19
     method strings are touched; nullParcelReleaseFunction (25nullParcel...,
     no "6Parcel") is left alone.

  2. patchelf --add-needed libm95shim_nparcel.so, so the box library is in
     librilimp's namespace and Pbrcel resolves.

Idempotent: re-running is a no-op (already-renamed + NEEDED present). Keeps the
pristine blob as librilimp.so.orig (or .<sha256 prefix> if .orig exists),
matching tools/blobpatch conventions in the 18.1 workspace.

Usage: librilimp-box-nparcel.py /path/to/vendor/lib64/librilimp.so
"""
import hashlib
import os
import re
import shutil
import struct
import subprocess
import sys

PRISTINE_SHA = "d3d8309e57861ec3946c56fe96535bc9c96aa838b57db4c4b2bdbed7a3550a47"
NEEDED = b"libm95shim_nparcel.so"
PATCHELF = os.path.expanduser("~/.local/bin/patchelf")

# The 19 out-of-line android::Parcel methods librilimp imports (mangled). Each
# occurs once in .dynstr and carries the substring "6Parcel" exactly once.
PARCEL_SYMS = [
    b"_ZN7android6Parcel10appendFromEPKS0_mm",
    b"_ZN7android6Parcel10writeInt32Ei",
    b"_ZN7android6Parcel10writeInt64El",
    b"_ZN7android6Parcel13writeString16EPKDsm",
    b"_ZN7android6Parcel13writeString16ERKNS_8String16E",
    b"_ZN7android6Parcel5writeEPKvm",
    b"_ZN7android6Parcel7setDataEPKhm",
    b"_ZN7android6ParcelC1Ev",
    b"_ZN7android6ParcelD1Ev",
    b"_ZNK7android6Parcel11readInplaceEm",
    b"_ZNK7android6Parcel12dataPositionEv",
    b"_ZNK7android6Parcel12readString16Ev",
    b"_ZNK7android6Parcel15setDataPositionEm",
    b"_ZNK7android6Parcel19readString16InplaceEPm",
    b"_ZNK7android6Parcel4dataEv",
    b"_ZNK7android6Parcel4readEPvm",
    b"_ZNK7android6Parcel8dataSizeEv",
    b"_ZNK7android6Parcel9readInt32EPi",
    b"_ZNK7android6Parcel9readInt32Ev",
]


def section(data, name):
    """Return (offset, size) of a section by name, or None."""
    e_shoff, = struct.unpack_from("<Q", data, 0x28)
    e_shentsize, e_shnum, e_shstrndx = struct.unpack_from("<HHH", data, 0x3A)
    sh = e_shoff + e_shstrndx * e_shentsize
    str_off, = struct.unpack_from("<Q", data, sh + 0x18)
    for i in range(e_shnum):
        o = e_shoff + i * e_shentsize
        nameoff, = struct.unpack_from("<I", data, o)
        end = data.index(b"\0", str_off + nameoff)
        if data[str_off + nameoff:end].decode() == name:
            addr_off = struct.unpack_from("<Q", data, o + 0x18)[0]
            size = struct.unpack_from("<Q", data, o + 0x20)[0]
            return addr_off, size
    return None


def backup(path):
    dst = path + ".orig"
    if os.path.exists(dst):
        pref = hashlib.sha256(open(path, "rb").read()).hexdigest()[:12]
        dst = path + "." + pref
        if os.path.exists(dst):
            return  # already have a copy of this exact blob
    shutil.copy2(path, dst)
    print("backup -> %s" % dst)


def rename_dynstr(path):
    data = bytearray(open(path, "rb").read())
    if data[:4] != b"\x7fELF" or data[4] != 2:
        sys.exit("%s: not a 64-bit ELF" % path)
    ds = section(data, ".dynstr")
    if not ds:
        sys.exit("no .dynstr")
    ds_off, ds_sz = ds
    seg = bytes(data[ds_off:ds_off + ds_sz])

    already = sum(seg.count(s.replace(b"6Parcel", b"6Pbrcel")) for s in PARCEL_SYMS)
    if already == len(PARCEL_SYMS):
        print("rename: already applied (19 Pbrcel strings present)")
        return False

    # Guard: exactly the 19 Parcel-method strings carry "android6Parcel"; the
    # only other Parcel string, nullParcelReleaseFunction, does not.
    hits = [m.start() for m in re.finditer(rb"android6Parcel", seg)]
    if len(hits) != len(PARCEL_SYMS):
        sys.exit("expected 19 'android6Parcel' occurrences in .dynstr, found %d"
                 % len(hits))
    for s in PARCEL_SYMS:
        if seg.count(s) != 1:
            sys.exit("symbol %r occurs %d times (want 1)" % (s, seg.count(s)))
    if seg.count(b"nullParcelReleaseFunction") != 1:
        sys.exit("nullParcelReleaseFunction guard failed")

    # In-place, same-length replacement of the token '6Parcel' -> '6Pbrcel',
    # but only where preceded by 'android' (so nullParcel* is never touched).
    for off in hits:
        pos = ds_off + off + len(b"android")  # points at '6Parcel'
        assert bytes(data[pos:pos + 7]) == b"6Parcel"
        data[pos:pos + 7] = b"6Pbrcel"

    open(path, "wb").write(data)
    print("rename: 19 android6Parcel -> android6Pbrcel in .dynstr")
    return True


def add_needed(path):
    have = subprocess.run([PATCHELF, "--print-needed", path],
                          capture_output=True, text=True).stdout.split()
    if NEEDED.decode() in have:
        print("add-needed: %s already present" % NEEDED.decode())
        return False
    subprocess.run([PATCHELF, "--add-needed", NEEDED.decode(), path], check=True)
    print("add-needed: %s" % NEEDED.decode())
    return True


def main(path):
    sha = hashlib.sha256(open(path, "rb").read()).hexdigest()
    if sha != PRISTINE_SHA:
        # Not fatal on re-run: it may already be boxed. Only warn if it is
        # neither pristine nor already-renamed.
        data = open(path, "rb").read()
        ds = section(bytearray(data), ".dynstr")
        seg = data[ds[0]:ds[0] + ds[1]] if ds else b""
        if b"android6Pbrcel" not in seg:
            print("WARNING: sha256 %s is neither pristine (%s) nor already "
                  "boxed; proceeding only if the guards below hold" %
                  (sha, PRISTINE_SHA))
    if sha == PRISTINE_SHA:
        backup(path)
    changed = rename_dynstr(path)
    changed |= add_needed(path)
    new = hashlib.sha256(open(path, "rb").read()).hexdigest()
    print("librilimp.so: %s -> %s" % (sha, new))
    print("changed" if changed else "no change (idempotent)")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
