#!/usr/bin/env python3
"""Offline-only Ibex QSPI Linux overlay/FIT packaging. Never accesses hardware."""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import struct
import subprocess

FLASH_BYTES = 32 * 2**20
FIT_OFFSET = 12 * 2**20


def digest(data):
    return hashlib.sha256(data).hexdigest()


def normalized(name):
    if name.startswith('./'):
        name = name[2:]
    if name == '.':
        return name
    if name.startswith('/') or any(p in ('', '.', '..') for p in name.split('/')):
        raise ValueError(f'unsafe archive name: {name}')
    return name


def parse_newc_streams(data):
    """Read every uncompressed newc stream, including device-node archives."""
    records, pos, active, stream = [], 0, False, 0
    while pos < len(data):
        if not active:
            while pos < len(data) and data[pos] == 0:
                pos += 1
            if pos == len(data):
                break
        start = pos
        header = data[pos:pos + 110]
        if len(header) != 110 or header[:6] not in (b'070701', b'070702'):
            raise ValueError(f'invalid newc header at {pos}')
        try:
            fields = [int(header[6 + i * 8:14 + i * 8], 16) for i in range(13)]
        except ValueError as error:
            raise ValueError('invalid newc hex fields') from error
        size, namesize = fields[6], fields[11]
        pos += 110
        namebytes = data[pos:pos + namesize]
        if not namesize or len(namebytes) != namesize or namebytes[-1:] != b'\0':
            raise ValueError('invalid newc name')
        name = normalized(namebytes[:-1].decode('utf-8'))
        pos = (pos + namesize + 3) & ~3
        payload = data[pos:pos + size]
        pos = (pos + size + 3) & ~3
        if len(payload) != size or pos > len(data):
            raise ValueError('truncated newc payload/padding')
        if header[:6] == b'070702' and (sum(payload) & 0xffffffff) != fields[12]:
            raise ValueError('newc checksum mismatch')
        if name == 'TRAILER!!!':
            active = False
            stream += 1
            continue
        active = True
        records.append(dict(name=name, fields=fields, content=payload, raw=data[start:pos],stream=stream))
    if active:
        raise ValueError('newc stream missing trailer')
    return records


def entry(name, content, mode, ino, rdev=(0, 0)):
    encoded = normalized(name).encode() + b'\0'
    fields = [ino, mode, 0, 0, 1, 0, len(content), 0, 0, *rdev, len(encoded), 0]
    block = b'070701' + b''.join(f'{v:08x}'.encode() for v in fields) + encoded
    block += bytes(-len(block) % 4)
    block += content
    return block + bytes(-len(block) % 4)


def overlay_initramfs(packed, replacements, device_nodes=None):
    originals = parse_newc_streams(gzip.decompress(packed))
    by_name = {e['name']: e for e in originals}
    ino = max((e['fields'][0] for e in originals), default=0) + 1
    chunks = []
    for name, (data, permissions) in replacements.items():
        normalized(name)
        if name in by_name and not stat.S_ISREG(by_name[name]['fields'][1]):
            raise ValueError(f'overlay target is not a regular file: {name}')
        for parent in PurePosixPath(name).parents:
            if str(parent) != '.' and (str(parent) not in by_name or not stat.S_ISDIR(by_name[str(parent)]['fields'][1])):
                raise ValueError(f'overlay parent is not an existing directory: {parent}')
        chunks.append(entry(name, data, stat.S_IFREG | permissions, ino))
        ino += 1
    for name, (permissions, major, minor) in (device_nodes or {}).items():
        normalized(name)
        parent=str(PurePosixPath(name).parent)
        if name in by_name or name in replacements or parent not in by_name or not stat.S_ISDIR(by_name[parent]['fields'][1]):
            raise ValueError(f'device overlay requires an absent node and existing directory: {name}')
        chunks.append(entry(name,b'',stat.S_IFCHR|permissions,ino,(major,minor)))
        ino += 1
    chunks.append(entry('TRAILER!!!', b'', 0, 0))
    overlay = b''.join(chunks)
    overlay += bytes(-len(overlay) % 512)
    result = packed + gzip.compress(overlay, mtime=0)
    verified = parse_newc_streams(gzip.decompress(result))
    if [e['raw'] for e in verified[:len(originals)]] != [e['raw'] for e in originals]:
        raise ValueError('original cpio records changed')
    final = {e['name']: e for e in verified}
    for name, (data, permissions) in replacements.items():
        if final[name]['content'] != data or final[name]['fields'][1] != stat.S_IFREG | permissions:
            raise ValueError(f'overlay verification failed: {name}')
    for name, (permissions, major, minor) in (device_nodes or {}).items():
        if final[name]['fields'][1] != stat.S_IFCHR|permissions or final[name]['fields'][9:11] != [major,minor]:
            raise ValueError(f'device overlay verification failed: {name}')
    return result


def device_additions(seed):
    additions={}
    # ttyPS0 has a dynamic major in the retained kernel. /init mounts devtmpfs
    # before its first tty access, so never create a guessed static tty node.
    for name,spec in {'dev/console':(0o600,5,1),'dev/null':(0o666,1,3)}.items():
        permissions,major,minor=spec
        if name in seed:
            fields=seed[name]['fields']
            if fields[1] != stat.S_IFCHR|permissions or fields[9:11] != [major,minor]:
                raise ValueError(f'conflicting existing device node: {name}')
        else:
            additions[name]=spec
    return additions


def patch_init(data):
    patterns = [rb'(?m)^/opt/sc130/start-platform\.sh[^\n]*\n',
                rb'(?m)^/opt/sc130/isp-tnr-startup\.sh[^\n]*\n']
    if any(len(re.findall(pattern, data)) != 1 for pattern in patterns):
        raise ValueError('expected one bridge launch and one PS profile launch in seed /init')
    data = re.sub(patterns[0], b'/opt/sc130/start-ibex-platform.sh >/tmp/ibex-startup.log 2>&1 &\n', data)
    return re.sub(patterns[1], b'', data)


def validate_sizes(boot_size, fit_size):
    if not 0 < boot_size <= FIT_OFFSET:
        raise ValueError('BOOT.BIN must fit below 0x00c00000')
    if not 0 < fit_size <= FLASH_BYTES - FIT_OFFSET:
        raise ValueError('FIT must fit within final 20 MiB')
    return FIT_OFFSET + fit_size


def verify_manifest(directory):
    entries = json.loads((directory / 'manifest.json').read_text())
    for e in entries:
        path = directory / Path(e['path']).name
        data = path.read_bytes()
        if len(data) != e['bytes'] or digest(data) != e['sha256']:
            raise ValueError(f'input manifest mismatch: {path}')


def verify_static_aarch64(data):
    if data[:6] != b'\x7fELF\x02\x01' or struct.unpack_from('<H', data, 18)[0] != 183:
        raise ValueError('payload is not little-endian AArch64 ELF64')
    offset = struct.unpack_from('<Q', data, 32)[0]
    size, count = struct.unpack_from('<HH', data, 54)
    if any(struct.unpack_from('<I', data, offset + n * size)[0] == 3 for n in range(count)):
        raise ValueError('dynamic PT_INTERP is forbidden')


def command(args, cwd=None):
    return subprocess.run(args, cwd=cwd, check=True, capture_output=True, text=True,
                          env={**os.environ, 'SOURCE_DATE_EPOCH': '0'}).stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference', type=Path, required=True)
    parser.add_argument('--boot-source', type=Path, required=True)
    parser.add_argument('--software', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--startup', type=Path, default=Path(__file__).with_name('start-ibex-platform.sh'))
    parser.add_argument('--iic-helper', type=Path, required=True)
    args = parser.parse_args()
    reference, software, out = args.reference.resolve(), args.software.resolve(), args.output.resolve()
    if out == reference or reference in out.parents or out == software or software in out.parents:
        raise ValueError('output must be independent of original seeds and frozen v3 deliverables')
    verify_manifest(reference)
    verify_manifest(args.boot_source)
    for line in (software / 'SHA256SUMS').read_text().splitlines():
        expected, name = line.split()
        if digest((software / name).read_bytes()) != expected:
            raise ValueError(f'v3 deliverable hash mismatch: {name}')
    boot = (out / 'BOOT.BIN').read_bytes()
    originals = parse_newc_streams(gzip.decompress((reference / 'initramfs.cpio.gz').read_bytes()))
    seed = {e['name']: e for e in originals}
    required = ['init', 'opt/sc130/start-platform.sh', 'opt/sc130/isp-tnr-startup.sh',
                'usr/bin/ispctl', 'usr/bin/tnrctl', 'dev']
    if any(name not in seed for name in required):
        raise ValueError('seed lacks required boot/startup/device records')
    replacements = {'init': (patch_init(seed['init']['content']), 0o755),
                    'opt/sc130/start-ibex-platform.sh': (args.startup.read_bytes().replace(b'\r\n', b'\n'), 0o755)}
    for name in ('sc130_platform_bridge', 'dp_smoke', 'ibex_isp_handoff'):
        data = (software / name).read_bytes()
        verify_static_aarch64(data)
        replacements['usr/bin/' + name] = (data, 0o755)
    helper=args.iic_helper.read_bytes()
    verify_static_aarch64(helper)
    replacements['usr/bin/ibex_iic_prepare']=(helper,0o755)
    nodes=device_additions(seed)
    initrd = overlay_initramfs((reference / 'initramfs.cpio.gz').read_bytes(), replacements,nodes)
    (out / 'initramfs.cpio.gz').write_bytes(initrd)
    for name in ('Image.gz', 'system.dtb', 'sc130.its'):
        shutil.copy2(reference / name, out / name)
    (out / 'mkimage.log').write_text(command(['mkimage', '-f', 'sc130.its', 'image.ub'], out))
    fit_hashes = {}
    for index, (node, filename) in enumerate((('kernel', 'Image.gz'), ('fdt', 'system.dtb'), ('ramdisk', 'initramfs.cpio.gz'))):
        extracted = out / f'verify-{filename}'
        command(['dumpimage', '-T', 'flat_dt', '-p', str(index), '-o', str(extracted), str(out / 'image.ub')])
        payload = extracted.read_bytes()
        if payload != (out / filename).read_bytes():
            raise ValueError(f'extracted FIT payload differs: {node}')
        stored = command(['fdtget', '-t', 'bx', str(out / 'image.ub'), f'/images/{node}/hash', 'value'])
        if bytes(int(x, 16) for x in stored.split()).hex() != digest(payload):
            raise ValueError(f'FIT hash mismatch: {node}')
        fit_hashes[node] = digest(payload)
        extracted.unlink()
    fit = (out / 'image.ub').read_bytes()
    end = validate_sizes(len(boot), len(fit))
    image = boot + b'\xff' * (FIT_OFFSET - len(boot)) + fit
    (out / 'QSPI_LINUX.bin').write_bytes(image)
    files = {name: {'bytes': (out / name).stat().st_size, 'sha256': digest((out / name).read_bytes())}
             for name in ('BOOT.BIN', 'image.ub', 'QSPI_LINUX.bin', 'Image.gz', 'system.dtb', 'initramfs.cpio.gz')}
    manifest = dict(reference=str(reference), software=str(software), files=files,
                    layout=dict(flash_bytes=FLASH_BYTES, fit_offset=FIT_OFFSET,
                                fit_max_bytes=FLASH_BYTES - FIT_OFFSET, image_bytes=end,
                                erase_bytes=(end + 0xffff) & ~0xffff),
                    cpio_original_records_preserved=len(originals),
                    cpio_original_streams=max((e['stream'] for e in originals),default=-1)+1,
                    original_initramfs_sha256=digest((reference / 'initramfs.cpio.gz').read_bytes()),
                    overlay={name: digest(data) for name, (data, _) in replacements.items()},
                    added_device_nodes=nodes,
                    fit_sha256=fit_hashes, r5_partition=False,
                    boot_inputs=json.loads((out/'boot-inputs.json').read_text()),
                    risk='USB ERROR buffers observed at 120 fps remain unresolved; see USB diagnosis report')
    (out / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    (out / 'SHA256SUMS').write_text(''.join(f"{info['sha256']}  {name}\n" for name, info in files.items()))
    (out / 'initramfs-members.txt').write_text('\n'.join(e['name'] for e in parse_newc_streams(gzip.decompress(initrd))) + '\n')
    print(json.dumps({'files': files, 'layout': manifest['layout'], 'preserved_records': len(originals)}, indent=2))


if __name__ == '__main__':
    main()
