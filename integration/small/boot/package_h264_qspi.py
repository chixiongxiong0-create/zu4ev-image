#!/usr/bin/env python3
"""Build a checked H264 FIT/QSPI artifact from a matched RAM/production BOOT.

Never accesses hardware. --overlay is a prepared runtime tree, including modules,
firmware and updated startup scripts; existing Ibex startup is preserved in seed.
"""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import shutil
import stat
import subprocess
from package_ibex_qspi import entry, parse_newc_streams, validate_sizes, FIT_OFFSET


def overlay_archive(seed, tree):
    records = parse_newc_streams(gzip.decompress(seed))
    existing = {r['name']: r for r in records}
    chunks = []
    ino = max(r['fields'][0] for r in records) + 1
    for path in sorted(tree.rglob('*'), key=lambda p: (len(p.parts), str(p))):
        name = path.relative_to(tree).as_posix()
        mode = path.lstat().st_mode
        prior = existing.get(name)
        if prior and stat.S_IFMT(prior['fields'][1]) != stat.S_IFMT(mode):
            raise ValueError(f'overlay changes file type: {name}')
        if path.is_symlink():
            import os
            payload = os.readlink(path).encode()
        elif path.is_dir():
            payload = b''
        elif path.is_file():
            payload = path.read_bytes()
        else:
            raise ValueError(f'unsupported overlay object: {name}')
        chunks.append(entry(name, payload, mode, ino))
        ino += 1
    chunks.append(entry('TRAILER!!!', b'', 0, ino))
    tail = b''.join(chunks)
    result = seed + gzip.compress(tail + bytes(-len(tail) % 512), mtime=0)
    final = {r['name']: r for r in parse_newc_streams(gzip.decompress(result))}
    for name in ('usr/bin/sc130_platform_bridge', 'opt/sc130/setup_uvc.sh',
                 'lib/firmware/al5e.fw', 'lib/firmware/al5e_b.fw'):
        if name not in final:
            raise ValueError(f'missing H264 runtime: {name}')
    return result


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for arg in ('seed', 'boot', 'kernel', 'dtb', 'overlay', 'output'):
        p.add_argument('--' + arg, type=Path, required=True)
    p.add_argument('--ram-test', action='store_true',
                   help='Produce a temporary DDR boot bundle, never a flash image')
    a = p.parse_args()
    out = a.output.resolve()
    if out.exists():
        raise ValueError('output must be a new directory')
    initrd = overlay_archive((a.seed / 'initramfs.cpio.gz').read_bytes(), a.overlay)
    out.mkdir(parents=True)
    shutil.copyfile(a.boot, out / 'BOOT.BIN')
    boot_inputs = a.boot.parent / 'boot-inputs.json'
    if boot_inputs.is_file():
        shutil.copyfile(boot_inputs, out / 'boot-inputs.json')
    (out / 'Image.gz').write_bytes(gzip.compress(a.kernel.read_bytes(), mtime=0))
    shutil.copyfile(a.dtb, out / 'system.dtb')
    shutil.copyfile(a.seed / 'sc130.its', out / 'sc130.its')
    (out / 'initramfs.cpio.gz').write_bytes(initrd)
    subprocess.run(['mkimage', '-f', 'sc130.its', 'image.ub'], cwd=out, check=True)
    for i, name in enumerate(('Image.gz', 'system.dtb', 'initramfs.cpio.gz')):
        check = out / ('verify-' + name)
        subprocess.run(['dumpimage', '-T', 'flat_dt', '-p', str(i), '-o', str(check),
                        str(out / 'image.ub')], check=True)
        if check.read_bytes() != (out / name).read_bytes():
            raise ValueError(f'FIT readback differs: {name}')
        check.unlink()
    boot, fit = (out / 'BOOT.BIN').read_bytes(), (out / 'image.ub').read_bytes()
    image_bytes = validate_sizes(len(boot), len(fit))
    if not a.ram_test:
        (out / 'QSPI_LINUX.bin').write_bytes(boot + b'\xff' * (FIT_OFFSET - len(boot)) + fit)
    files = {}
    names = ['BOOT.BIN', 'image.ub', 'Image.gz', 'system.dtb', 'initramfs.cpio.gz']
    if not a.ram_test:
        names.append('QSPI_LINUX.bin')
    for name in names:
        data = (out / name).read_bytes()
        files[name] = dict(bytes=len(data), sha256=hashlib.sha256(data).hexdigest())
    (out / 'manifest.json').write_text(json.dumps(dict(files=files, fit_offset=FIT_OFFSET,
        flashable=not a.ram_test, boot_kind='ramtest' if a.ram_test else 'production',
        layout=dict(flash_bytes=32 * 2**20, fit_offset=FIT_OFFSET,
                    image_bytes=image_bytes, erase_bytes=(image_bytes + 0xffff) & ~0xffff),
        boot_inputs=json.loads(boot_inputs.read_text(encoding='utf-8-sig')) if boot_inputs.is_file() else None,
        hardware_verified=False, note='Offline packaging only; see separate board validation report.'), indent=2) + '\n')
    (out / 'SHA256SUMS').write_text(''.join(f"{v['sha256']}  {k}\n" for k, v in files.items()))
    print('H264_QSPI_PACKAGE_PASS', out)


if __name__ == '__main__':
    main()
