#!/usr/bin/env python3
"""Apply the overlapping framebased patch series atomically and idempotently."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
PATCHES = [HERE / 'patches' / name for name in (
    '0007-uvc-framebased.patch', '0008-uvc-framebased-color-matching.patch',
    '0009-uvc-framebased-buffer-capacity.patch')]
FILES = ('Documentation/ABI/testing/configfs-usb-gadget-uvc',
         'drivers/usb/gadget/function/uvc_configfs.c',
         'drivers/usb/gadget/function/uvc_configfs.h',
         'drivers/usb/gadget/function/uvc_v4l2.c',
         'include/uapi/linux/usb/video.h')

def patch(tree, patchfile, reverse=False, dry=False):
    # Never let patch silently flip direction when probing an absent patch.
    command = ['patch', '--batch', '--force', '-p1', '-d', str(tree)]
    if reverse:
        command.append('-R')
    if dry:
        command.append('--dry-run')
    return subprocess.run(command, input=patchfile.read_bytes(),
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

def main():
    source = Path(sys.argv[1]).resolve()
    with tempfile.TemporaryDirectory(prefix='sc130-uvc-patches-') as tmp:
        tree = Path(tmp)
        for name in FILES:
            target = tree / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source / name, target)
        # Later patches edit earlier patch context. Undo in reverse series
        # order in scratch storage, then reconstruct the complete desired tree.
        for item in reversed(PATCHES):
            if patch(tree, item, reverse=True, dry=True).returncode == 0:
                result = patch(tree, item, reverse=True)
                if result.returncode:
                    raise RuntimeError(result.stdout.decode(errors='replace'))
        for item in PATCHES:
            result = patch(tree, item)
            if result.returncode:
                raise RuntimeError(f'{item.name}: {result.stdout.decode(errors="replace")}')
        for name in FILES:
            if (source / name).read_bytes() != (tree / name).read_bytes():
                shutil.copy2(tree / name, source / name)
    print('H264_UVC_PATCH_SERIES_PASS')

if __name__ == '__main__':
    main()
