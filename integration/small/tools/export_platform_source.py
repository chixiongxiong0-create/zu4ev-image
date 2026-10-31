#!/usr/bin/env python3
"""Export only named, hashed platform sources; never inspect Vivado outputs."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import subprocess


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    repo=Path(__file__).resolve().parents[3]
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle',type=Path,default=repo/'build/ibex_small/isp_master_v3_20261030')
    parser.add_argument('--qspi',type=Path,default=repo/'build/ibex_small/qspi_v3_20261031')
    parser.add_argument('--platform',type=Path,default=Path('E:/workspace/AI_Projects/ZU4EV/zynq-zu4ev_platform'))
    parser.add_argument('--sdk',type=Path,default=Path('D:/Xilinx/2025.1/data/embeddedsw'))
    parser.add_argument('--gpl-license',type=Path,help='GPL-2.0 license text from the retained Linux source')
    parser.add_argument('--output',type=Path,default=repo/'platform/zu4ev')
    args=parser.parse_args()
    out=args.output.resolve()
    if out.exists():
        raise ValueError('publication output must not already exist')
    files={}
    excluded=[]
    allowed={'.c','.h','.S','.sv','.svh','.v','.vh','.tcl','.xdc','.py','.sh',
             '.ps1','.ld','.md','.json','.mem','.coe','.dts','.dtsi','.patch','.txt'}

    def add(source,destination,origin,expected=None,upstream=None):
        relative=PurePosixPath(destination)
        if relative.is_absolute() or '..' in relative.parts:
            raise ValueError(f'unsafe destination {destination}')
        if source.is_symlink() or not source.is_file():
            raise ValueError(f'missing/nonregular source {source}')
        if source.suffix.lower() not in {x.lower() for x in allowed} and source.name not in ('Makefile','rawctl','MIT','GPL-2.0'):
            raise ValueError(f'not an approved source type: {source}')
        data=source.read_bytes()
        if data.startswith(b'\x7fELF') or b'\0' in data:
            raise ValueError(f'binary payload forbidden: {source}')
        digest=sha(data)
        if expected and digest!=expected:
            raise ValueError(f'frozen source hash mismatch: {source}')
        record=dict(path=relative.as_posix(),bytes=len(data),sha256=digest,origin=origin)
        if upstream: record['upstream_sha256']=upstream
        if destination in files and files[destination][1]['sha256']!=digest:
            raise ValueError(f'conflicting source destination {destination}')
        files[destination]=(data,record)

    original=json.loads((args.bundle/'source_manifest.json').read_text())
    integrated=json.loads((args.bundle/'integration_manifest.json').read_text())
    base={e['path']:e for e in original['files']}
    patches={e['path']:e['sha256'] for e in integrated['patched_files']}
    for name in sorted(set(base)|set(patches)):
        if '.vscode' in PurePosixPath(name).parts:
            excluded.append(dict(path=name,reason='machine/editor settings'))
            continue
        target='README.upstream.md' if name=='README.md' else name
        entry=base.get(name,{})
        expected=patches.get(name,entry.get('snapshot_sha256'))
        add(args.bundle/name,target,'frozen-v3/'+name,expected,entry.get('source_sha256'))

    # Fixed bounded auxiliary source lists, never generated project/run trees.
    boot_files=[
        'boot/build_atf.sh','boot/build_uboot.sh','boot/build_uboot_ramtest.sh',
        'boot/build_boot_bin.ps1','boot/package_qspi.py','boot/test_package_qspi.py',
        'boot/bin_to_mcs.py','boot/zumini-sc130-qspi.dts',
        'boot/fsbl/prepare_fsbl.py','boot/fsbl/check_layout.py','boot/fsbl/build_fsbl.ps1',
        'boot/fsbl/README.md','boot/fsbl/sc130_power.c','boot/fsbl/sc130_sensor_start.c',
        'boot/fsbl/ram_boot_support.c','boot/fsbl/test_prepare.py','boot/fsbl/tests/test_power.c',
        'boot/fsbl/camera/camera_pipeline.c','boot/fsbl/camera/camera_pipeline.h',
        'boot/fsbl/camera/sensor_i2c.c','boot/fsbl/camera/sc130_table.h']
    linux_files=[
        'linux/README.md','linux/build.sh','linux/initramfs-init.sh','linux/start-platform.sh',
        'linux/setup_uvc.sh','linux/tune-irq.sh','linux/flash-boot.c','linux/stage-frame.c',
        'linux/raw10check.c','linux/rawctl',
        'linux/kernel/Makefile','linux/kernel/dual_core.h','linux/kernel/sc130_capture.c',
        'linux/kernel/sc130_raw_capture.c','linux/kernel/sc130_contract.h',
        'linux/kernel/raw_capture_contract.c','linux/kernel/raw_capture_contract.h',
        'linux/dt/sc130-uvc.dts','linux/dt/sc130-pl.dtsi',
        'linux/patches/0001-uvc-allow-ss-only-descriptors.patch',
        'linux/patches/0002-vdma-export-halted-query.patch',
        'linux/patches/0003-zynqmp-vblank-on-active-modeset-only.patch',
        'linux/patches/0004-vdma-single-frame-program-all-address-slots.patch',
        'linux/patches/0005-dp-fast-detect-and-connect-poll.patch',
        'linux/patches/0006-vdma-error-query.patch',
        'linux/tests/test_dual.c','linux/tests/test_raw_capture_contract.c',
        'linux/tests/test_package.py','linux/tests/test_dp_hpd_poll.py',
        'linux/tests/test_vblank_restore.py','linux/tests/test_stage_cli.py',
        'linux/tests/test_stage_frame.c']
    for name in boot_files+linux_files:
        add(args.platform/name,name,'original-platform/'+name)

    prod_dir=args.qspi/'fsbl-production'
    ram_dir=args.qspi/'fsbl-ramtest'
    prod=json.loads((prod_dir/'source-manifest.json').read_text())
    ram=json.loads((ram_dir/'source-manifest.json').read_text())
    differences=[n for n in set(prod['prepared'])|set(ram['prepared']) if prod['prepared'].get(n)!=ram['prepared'].get(n)]
    if differences!=['xfsbl_qspi.c']:
        raise ValueError(f'unexpected prepared variant differences: {differences}')
    for name,digest in sorted(prod['prepared'].items()):
        add(prod_dir/'source'/name,'boot/fsbl/prepared/'+name,'frozen-production-fsbl/'+name,digest)
    add(ram_dir/'source/xfsbl_qspi.c','boot/fsbl/ramtest/xfsbl_qspi.c',
        'frozen-ramtest-fsbl/xfsbl_qspi.c',ram['prepared']['xfsbl_qspi.c'])
    # Raw generated application sources are enough for the existing preparer;
    # externally supplied BSP headers/libraries remain required for linking.
    for path,digest in prod['inputs'].items():
        source=Path(path)
        marker='firmware/boot_reference/zynqmp_fsbl'
        normalized=source.as_posix()
        if marker+'/' in normalized:
            relative=normalized[normalized.index(marker):]
            add(source,relative,'generated-fsbl-application/'+source.name,digest)

    add(args.sdk/'LICENSES/MIT','LICENSES/AMD-Xilinx-MIT.txt','vitis-2025.1/LICENSES/MIT')
    if args.gpl_license:
        gpl=args.gpl_license.read_bytes()
    else:
        gpl=subprocess.check_output(['wsl','-e','cat',
            '/home/developer/zu4ev/sc130-platform-build/linux-src/LICENSES/preferred/GPL-2.0'])
    files['LICENSES/GPL-2.0.txt']=(gpl,dict(path='LICENSES/GPL-2.0.txt',bytes=len(gpl),
        sha256=sha(gpl),origin='linux-source/LICENSES/preferred/GPL-2.0'))
    # Complete all validation before any publication writes.
    for name,(data,_) in files.items():
        target=out/name
        target.parent.mkdir(parents=True,exist_ok=True)
        target.write_bytes(data)
    for name,(data,_) in files.items():
        if (out/name).read_bytes()!=data:
            raise ValueError(f'copy verification failed: {name}')
    manifest=dict(format=1,scope='source-only publication; no SDK libraries or compiled artifacts',
        inputs={name:sha((args.bundle/name).read_bytes()) for name in ('source_manifest.json','integration_manifest.json')},
        fsbl_prepared_variant_differences=differences,excluded=excluded,
        files=[record for _,record in sorted(files.values(),key=lambda e:e[1]['path'])])
    (out/'source_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(dict(output=str(out),files=len(files),bytes=sum(len(data) for data,_ in files.values()),
                          excluded=excluded,fsbl_prepared_variant_differences=differences),indent=2))


if __name__=='__main__': main()
