#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Make the Android 7 camera Looper allocation fit the VNDK33 Looper ABI."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import stat
import struct
import tempfile

PAIRS={
    '1772c3541c0ff57a4a73b523865f5b1a121e98191fb104fa0f26386089af423b':
        '5b4b1d232db6b2a1e790111186ab96baf9c67fa9c394fed49ef42dcb59284fd4',
    'c2026ac397fcc9fa3f336c019e54fc9cccbbf2338779266e7697344558939ff4':
        '70eb45f7f7071c309d03bcbd11c15167ecd714472483bfd777a40eea0a101228',
}

def digest(data):return hashlib.sha256(data).hexdigest()

def allocation_offset(data):
    if data[:7]!=b'\x7fELF\x01\x01\x01' or struct.unpack_from('<H',data,18)[0]!=40:
        raise ValueError('expected ARM32 little-endian library')
    phoff=struct.unpack_from('<I',data,28)[0]
    phsize,phcount=struct.unpack_from('<HH',data,42)
    for index in range(phcount):
        kind,offset,va,_,filesize=struct.unpack_from('<IIIII',data,phoff+phsize*index)
        if kind==1 and va<=0x31C8 and 0x31C8+4<=va+filesize:
            return offset+0x31C8-va
    raise ValueError('allocation instruction is not file backed')

def fixed(data):
    sha=digest(data)
    if sha in PAIRS.values():return data,False
    if sha not in PAIRS:raise ValueError('unknown libmtkcam_sysutils.so; refusing patch')
    offset=allocation_offset(data)
    if data[offset:offset+4]!=bytes.fromhex('7020fef7'):
        raise ValueError('allocation instruction differs')
    output=bytearray(data);output[offset]=0x88;output=bytes(output)
    if digest(output)!=PAIRS[sha]:raise ValueError('patched library SHA mismatch')
    return output,True

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--file',required=True)
    parser.add_argument('--abi',choices=['vndk33-looper136'],required=True)
    parser.add_argument('--apply',action='store_true')
    args=parser.parse_args()
    path=Path(args.file)
    original=path.read_bytes();output,changed=fixed(original)
    if changed and args.apply:
        mode=stat.S_IMODE(path.stat().st_mode)
        # Preserve a verified original outside the Git payload list.
        backup=path.with_name(path.name+'.looper112-original')
        if backup.exists():
            if digest(backup.read_bytes())!=digest(original):
                raise ValueError('original backup differs')
        else:
            with os.fdopen(os.open(backup,os.O_WRONLY|os.O_CREAT|os.O_EXCL,mode),'wb') as stream:
                stream.write(original)
        fd,name=tempfile.mkstemp(prefix='.camera-looper-',dir=path.parent)
        with os.fdopen(fd,'wb') as stream:
            stream.write(output);stream.flush();os.fsync(stream.fileno())
        os.chmod(name,mode)
        os.replace(name,path)
    print(json.dumps(dict(original_sha256=digest(original),patched_sha256=digest(output),
                          needs_patch=changed,applied=bool(changed and args.apply)),sort_keys=True))

if __name__=='__main__':main()
