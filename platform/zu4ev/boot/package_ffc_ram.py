#!/usr/bin/env python3
"""Package an FFC/DPC FIT from the validated NV12 kernel/rootfs seed."""
import argparse,gzip,hashlib,json,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'integration/small/boot'))
from package_ibex_qspi import FIT_OFFSET,entry,parse_newc_streams,validate_sizes
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--seed',type=Path,required=True);p.add_argument('--tools',type=Path,required=True)
p.add_argument('--output',type=Path,required=True)
p.add_argument('--dpcctl',type=Path,help='include the DPC control tool')
p.add_argument('--production-boot',type=Path,
               help='BOOT.BIN built with production FSBL and U-Boot; enables QSPI output')
p.add_argument('--ffc-map',type=Path,help='package the dark FFC table for manual loading')
p.add_argument('--dpc-map',type=Path,help='package the confirmed DPC table for manual loading')
a=p.parse_args()
if a.output.exists():raise ValueError('output must be new')
if a.dpc_map and not a.dpcctl:p.error('--dpc-map requires --dpcctl')
seed=(a.seed/'initramfs.cpio.gz').read_bytes()
entries=[('usr/bin/ffcctl',(a.tools/'ffcctl').read_bytes(),0o100755),
         ('usr/bin/ffc_sensor_meta',(a.tools/'ffc_sensor_meta').read_bytes(),0o100755)]
if a.dpcctl:entries.append(('usr/bin/dpcctl',a.dpcctl.read_bytes(),0o100755))
for path,name in ((a.ffc_map,'dark-2243.map'),(a.dpc_map,'dark.dpc')):
 if path:entries.append(('opt/sc130/'+name,path.read_bytes(),0o100644))
if not a.production_boot:
 records=parse_newc_streams(gzip.decompress(seed));final={r['name']:r for r in records}
 init=final['init']['content']
 needle=b'/opt/sc130/start-ibex-platform.sh'
 if init.count(needle)!=1:raise ValueError('unexpected init coordinator')
 calibration=b'''# RAM-only dark acquisition, while the owner is PS and before AE changes exposure.
/usr/bin/ibex_isp_handoff stop >/tmp/ffc-initial-stop.log 2>&1
if [ "$?" = 0 ]; then
 /usr/bin/ffc_sensor_meta --clock-confirmed calibration-probe >/tmp/ffc-sensor-meta.log 2>&1
 if [ "$?" = 0 ]; then
  /usr/bin/ffcctl capture /tmp/ffc-dark-auto.stats >/tmp/ffc-capture.log 2>&1
 fi
fi
'''
 init=init.replace(needle,calibration+needle)
 # Keep sensor exposure/gain fixed for the host's original/corrected comparison.
 coordinator=final['opt/sc130/start-ibex-platform.sh']['content']
 handoff=b'/usr/bin/ibex_iic_prepare --boot-before-handoff'
 if coordinator.count(handoff)!=1:raise ValueError('unexpected handoff coordinator')
 coordinator=coordinator.replace(handoff,b"echo 'FFC_CALIBRATION_HOLD: touch /tmp/ffc-allow-ae after measurement'\nwhile [ ! -e /tmp/ffc-allow-ae ]; do sleep 1; done\n"+handoff)
 entries.extend([('opt/sc130/start-ibex-platform.sh',coordinator,0o100755),
                 ('init',init,0o100755)])
chunks=[]
for i,(name,data,mode) in enumerate(entries):
 chunks.append(entry(name,data,mode,900000+i))
chunks.append(entry('TRAILER!!!',b'',0,900010));tail=b''.join(chunks)
archive=seed+gzip.compress(tail+bytes(-len(tail)%512),mtime=0)
check={r['name']:r for r in parse_newc_streams(gzip.decompress(archive))}
for name,data,mode in entries:
 if check[name]['fields'][1]!=mode or check[name]['content']!=data:
  raise ValueError(f'archive readback mismatch: {name}')
a.output.mkdir(parents=True)
(a.output/'initramfs.cpio.gz').write_bytes(archive)
for name in ['Image.gz','system.dtb']:(a.output/name).write_bytes((a.seed/name).read_bytes())
description='Mono FFC/DPC NV12 QSPI' if a.production_boot else 'Mono FFC NV12 RAM-only validation'
(a.output/'sc130.its').write_text((a.seed/'sc130.its').read_text().replace('SC130 NV12 RAM-only validation',description))
subprocess.run(['mkimage','-f','sc130.its','image.ub'],cwd=a.output,check=True,stdout=subprocess.DEVNULL)
for i,name in enumerate(['Image.gz','system.dtb','initramfs.cpio.gz']):
 test=a.output/('verify-'+name)
 subprocess.run(['dumpimage','-T','flat_dt','-p',str(i),'-o',str(test),str(a.output/'image.ub')],check=True,stdout=subprocess.DEVNULL)
 if test.read_bytes()!=(a.output/name).read_bytes():raise ValueError('FIT mismatch')
 test.unlink()
manifest={'flashable':bool(a.production_boot),'dark_acquisition_only':not a.production_boot}
if a.production_boot:
 boot=a.production_boot.read_bytes()
 fit=(a.output/'image.ub').read_bytes()
 image_size=validate_sizes(len(boot),len(fit))
 (a.output/'BOOT.BIN').write_bytes(boot)
 (a.output/'QSPI_LINUX.bin').write_bytes(boot+b'\xff'*(FIT_OFFSET-len(boot))+fit)
 manifest.update(fit_offset=FIT_OFFSET,image_bytes=image_size,
                 erase_bytes=(image_size+0xffff)&~0xffff,hardware_verified=False)
files={f.name:{'bytes':f.stat().st_size,'sha256':hashlib.sha256(f.read_bytes()).hexdigest()} for f in a.output.iterdir() if f.is_file()}
manifest['files']=files
(a.output/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
(a.output/'SHA256SUMS').write_text(''.join(f"{v['sha256']}  {k}\n" for k,v in sorted(files.items())))
print('FFC_QSPI_PACKAGE_PASS' if a.production_boot else 'FFC_RAM_FIT_PASS',a.output)
