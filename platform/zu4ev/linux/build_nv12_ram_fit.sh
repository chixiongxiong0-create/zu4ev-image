#!/bin/bash
# RAM validation FIT only: no flash image and no hardware access.
set -euo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd -- "$HERE/../../.." && pwd)
BASE=$REPO/build/h264_release/ramtest-recovery
RUNTIME=$REPO/build/nv12_platform/runtime
OUT=$REPO/build/nv12_platform/ram_candidate
KOUT=${SC130_H264_KERNEL_OUT:-/home/developer/zu4ev/sc130-h264-build}
mkdir -p "$OUT"
test -s "$RUNTIME/overlay/opt/sc130/sc130_nv12.ko"
old_hash=$(gzip -dc "$BASE/Image.gz" | sha256sum | cut -d' ' -f1)
current_hash=$(sha256sum "$KOUT/arch/arm64/boot/Image" | cut -d' ' -f1)
[[ "$old_hash" == "$current_hash" ]] || { echo 'Baseline kernel does not match module build headers';exit 2; }
python3 - "$RUNTIME/overlay" "$OUT/overlay.list" <<'PY'
from pathlib import Path
import sys
root=Path(sys.argv[1]).resolve();lines=[]
for p in sorted(root.rglob('*'),key=lambda p:(len(p.parts),str(p))):
 rel=p.relative_to(root).as_posix()
 if p.is_symlink():raise SystemExit('Unexpected overlay symlink')
 if any(c.isspace() for c in str(p)):raise SystemExit('gen_init_cpio source paths must have no whitespace')
 if p.is_dir():lines.append(f'dir /{rel} 0755 0 0')
 elif p.is_file():
  mode='0755' if rel.startswith('usr/bin/') or p.suffix=='.sh' else '0644'
  lines.append(f'file /{rel} {p} {mode} 0 0')
Path(sys.argv[2]).write_text('\n'.join(lines)+'\n')
PY
"$KOUT/usr/gen_init_cpio" "$OUT/overlay.list" > "$OUT/overlay.cpio"
{ gzip -dc "$BASE/initramfs.cpio.gz"; cat "$OUT/overlay.cpio"; } | gzip -n > "$OUT/initramfs.cpio.gz"
cp "$BASE/Image.gz" "$OUT/Image.gz"
cp "$RUNTIME/sc130-nv12.dtb" "$OUT/system.dtb"
sed 's/SC130 unified QSPI Linux/SC130 NV12 RAM-only validation/' "$BASE/sc130.its" > "$OUT/sc130.its"
(cd "$OUT"; mkimage -f sc130.its image.ub > mkimage.log)
[[ $(stat -c%s "$OUT/image.ub") -le 20971520 ]] || { echo 'RAM FIT exceeds staging limit';exit 2; }
python3 - "$OUT" <<'PY'
from pathlib import Path
import hashlib,json,sys
p=Path(sys.argv[1]);names=['Image.gz','system.dtb','initramfs.cpio.gz','image.ub']
manifest={'flashable':False,'boot_kind':'ramtest','nv12':True,'files':{n:{'bytes':(p/n).stat().st_size,'sha256':hashlib.sha256((p/n).read_bytes()).hexdigest()} for n in names}}
(p/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print('NV12_RAM_FIT_PASS bytes='+str((p/'image.ub').stat().st_size))
PY
