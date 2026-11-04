"""Generate a signed-AOT input from a hash-pinned official upstream APK.

No APK, ELF, generated instruction source or snapshot belongs in git.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import urllib.request
import zipfile
import emit_first_host

ROOT = Path(__file__).resolve().parents[2]
APK_URL = 'https://github.com/SoldadoGhost/T6Requiem-APK/releases/download/v2.1.0-beta/T6Requiem-2.1.0-beta.apk'
APK_SHA = '5f49507caf46e6f3e00c5cc03a62c5768cb0d2d33bb692e367e219ccb6e2f628'
GUEST_SHA = 'b33b9a743e03c92eee76f495e81c007f1762b87b3c58356fd23d1967c839f9d3'
VM_SIZE = 0x5000000


def checked_image(data):
    if hashlib.sha256(data).hexdigest() != GUEST_SHA:
        raise ValueError('Upstream guest identity mismatch')
    if data[:6] != b'\x7fELF\x01\x01':
        raise ValueError('Expected little-endian ELF32')
    phoff = struct.unpack_from('<I', data, 28)[0]
    size, count = struct.unpack_from('<HH', data, 42)
    headers = [struct.unpack_from('<IIIIIIII', data, phoff+i*size) for i in range(count)]
    loads = [s for s in headers if s[0] == 1]
    memory = bytearray(VM_SIZE)
    for _, offset, address, _, file_size, memory_size, _, _ in loads:
        if file_size > memory_size or address+memory_size > VM_SIZE or offset+file_size > len(data):
            raise ValueError('Invalid PT_LOAD extent')
        memory[address:address+file_size] = data[offset:offset+file_size]
    dynamic = next(s for s in headers if s[0] == 2)
    entries = dict(struct.unpack_from('<II', data, i) for i in range(dynamic[1], dynamic[1]+dynamic[4], 8))
    rela, length, entry_size = entries[7], entries[8], entries[9]
    if entry_size != 12 or length % 12:
        raise ValueError('Unsupported P32 relocation layout')
    relocations = 0
    for offset in range(rela, rela+length, entry_size):
        destination, info, addend = struct.unpack_from('<IIi', memory, offset)
        if info & 255 != 183 or info >> 8:
            raise ValueError('Unsupported relocation')
        if not any(s[6] & 2 and s[2] <= destination and destination+4 <= s[2]+s[5] for s in loads):
            raise ValueError('Relocation destination is not guest writable data')
        struct.pack_into('<I', memory, destination, addend & 0xffffffff)
        relocations += 1
    if relocations != 135795:
        raise ValueError('Unexpected relocation count')
    return memory, relocations, max(s[2]+s[5] for s in loads)


def main():
    inputs = ROOT/'GeneratedInputs'
    inputs.mkdir(exist_ok=True)
    apk = Path(os.environ.get('AOT_APK_PATH', inputs/'T6Requiem.apk'))
    if not apk.exists():
        request = urllib.request.Request(APK_URL, headers={'User-Agent': 'BO2-iOS-build'})
        with urllib.request.urlopen(request, timeout=120) as response, apk.open('wb') as out:
            shutil.copyfileobj(response, out)
    if hashlib.sha256(apk.read_bytes()).hexdigest() != APK_SHA:
        raise ValueError('Official APK SHA256 mismatch')
    with zipfile.ZipFile(apk) as archive:
        guest = archive.read('assets/guest/t6mp_guest.elf')
    snapshot, relocation_count, image_end = checked_image(guest)
    native = ROOT/'Generated/CAOTEngine'
    swift = ROOT/'Generated/AOTCore'
    resources = swift/'Resources'
    (native/'include').mkdir(parents=True, exist_ok=True)
    resources.mkdir(parents=True, exist_ok=True)
    source, unsupported = emit_first_host.generate(guest)
    (native/'engine.inc').write_text(source)
    shutil.copyfile(ROOT/'Sources/AOTSupport/CAOTEngine.h', native/'include/CAOTEngine.h')
    shutil.copyfile(ROOT/'Sources/AOTSupport/Bridge.c', native/'Bridge.c')
    shutil.copyfile(ROOT/'Sources/AOTSupport/AOTCore.swift', swift/'AOTCore.swift')
    (resources/'VMImage.bin').write_bytes(snapshot)
    metadata = {
        'apkURL': APK_URL, 'apkSHA256': APK_SHA, 'guestSHA256': GUEST_SHA,
        'snapshotSHA256': hashlib.sha256(snapshot).hexdigest(),
        'generatedCodeSHA256': hashlib.sha256(source.encode()).hexdigest(),
        'imageEnd': image_end, 'relocationCount': relocation_count,
        'generation': 'build-time PT_LOAD copy, BSS zero-fill and P32 relative relocations; logical bias zero',
        'commit': os.environ.get('GITHUB_SHA') or subprocess.check_output(['git','rev-parse','HEAD'], cwd=ROOT, text=True).strip(),
        'scope': 'finite MP initialization through first logging import; no gameplay, JIT or original ARM64 execution',
        'unsupportedStaticInstructions': len(unsupported)
    }
    (resources/'ImageMetadata.json').write_text(json.dumps(metadata, indent=2)+'\n')
    print(json.dumps({k: metadata[k] for k in ('guestSHA256','snapshotSHA256','relocationCount','imageEnd','commit')}))


if __name__ == '__main__':
    main()
