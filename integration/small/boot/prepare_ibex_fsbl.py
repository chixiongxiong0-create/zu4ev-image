#!/usr/bin/env python3
"""Prepare isolated production/RAM FSBL with the same PS-IIC implementation."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import stat
import subprocess
import sys


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--platform',type=Path,required=True)
    parser.add_argument('--driver',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--ram-test',action='store_true')
    args=parser.parse_args()
    original=args.platform.resolve()
    generated=original/'firmware/boot_reference/zynqmp_fsbl'
    out=args.output.resolve()
    if out==original or original in out.parents:
        raise ValueError('FSBL output must not be in original platform')
    command=[sys.executable,str(original/'boot/fsbl/prepare_fsbl.py'),
             '--source',str(generated),'--output',str(out)]
    if args.ram_test: command.append('--ram-test')
    subprocess.run(command,check=True)
    sensor=out/'sensor_i2c.c'
    data=sensor.read_text()
    anchor='    XIicPs_Config cfg = {0};'
    if data.count(anchor)!=1 or 'cfg.InputClockHz = 100000000U;' not in data:
        raise ValueError('current PS-IIC source with known InputClockHz required')
    sensor.write_text(data.replace(anchor,'    extern int sc130_iic_clock_prepare(void);\n'
                                  '    if (sc130_iic_clock_prepare()) return SENSOR_FAILED;\n'+anchor))
    here=Path(__file__).resolve().parent
    shutil.copy2(here/'sc130_iic_clock.c',out/'sc130_iic_clock.c')
    # The seed BSP predates PS IIC enable. Use current unmodified official
    # polled driver directly with its explicitly constructed XIicPs_Config.
    sources=['xiicps.c','xiicps_hw.c','xiicps_master.c','xiicps_options.c','xiicps_xfer.c']
    sources += [p.name for p in args.driver.glob('*.h')]
    for name in sources:
        target=out/name
        if target.exists(): target.chmod(target.stat().st_mode | stat.S_IWUSR)
        shutil.copyfile(args.driver/name,target)
    inputs=[*generated.glob('*.c'),*generated.glob('*.h'),*generated.glob('*.S'),*generated.glob('*.ld'),
            *[args.driver/name for name in sources],here/'sc130_iic_clock.c',Path(__file__).resolve(),
            original/'boot/fsbl/prepare_fsbl.py',original/'boot/fsbl/camera/sensor_i2c.c']
    manifest={'ram_test':args.ram_test,'generated_source':str(generated),'driver':str(args.driver),
              'inputs':{str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs},
              'prepared':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in out.iterdir() if p.is_file()}}
    (out.parent/'source-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')


if __name__=='__main__': main()
