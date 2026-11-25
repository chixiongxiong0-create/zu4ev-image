#!/usr/bin/env python3
"""Verify UVC backport idempotence from absent, partial, and complete states."""
import importlib.util
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

helper = Path(__file__).resolve().parents[1] / 'apply_h264_uvc_patches.py'
spec = importlib.util.spec_from_file_location('uvc_series', helper)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
source = Path(sys.argv[1])
with tempfile.TemporaryDirectory(prefix='uvc-series-test-') as tmp:
    tree = Path(tmp)
    expected = {name: (source / name).read_bytes() for name in module.FILES}
    for name in module.FILES:
        (tree / name).parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source / name, tree / name)
    # Normalize the supplied installed source before testing partial states.
    subprocess.run([sys.executable, str(helper), str(tree)], check=True)
    expected = {name: (tree / name).read_bytes() for name in module.FILES}
    for undo in (0, 1, 2, 3):
        for name, data in expected.items():
            (tree / name).write_bytes(data)
        for patchfile in list(reversed(module.PATCHES))[:undo]:
            result = module.patch(tree, patchfile, reverse=True)
            assert result.returncode == 0, result.stdout
        subprocess.run([sys.executable, str(helper), str(tree)], check=True)
        assert all((tree / name).read_bytes() == data for name, data in expected.items())
    print('H264 patch absent/partial/complete idempotence: PASS')
