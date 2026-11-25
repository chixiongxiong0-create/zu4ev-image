import gzip
import importlib.util
import stat
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
spec = importlib.util.spec_from_file_location('h264_pack', ROOT / 'package_h264_qspi.py')
pack = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pack)


class H264PackageTest(unittest.TestCase):
    def seed(self):
        return gzip.compress(pack.entry('dev/console', b'', stat.S_IFCHR | 0o600, 1, (5, 1))
                             + pack.entry('TRAILER!!!', b'', 0, 2), mtime=0)

    def test_nested_runtime_preserves_device_and_replaces_regular_file(self):
        with tempfile.TemporaryDirectory() as d:
            tree = Path(d)
            names = ('usr/bin/sc130_platform_bridge', 'opt/sc130/setup_uvc.sh',
                     'lib/firmware/al5e.fw', 'lib/firmware/al5e_b.fw')
            for name in names:
                path = tree / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(name.encode())
            result = pack.overlay_archive(self.seed(), tree)
            records = {r['name']: r for r in pack.parse_newc_streams(gzip.decompress(result))}
            self.assertEqual(records['dev/console']['fields'][9:11], [5, 1])
            for name in names:
                self.assertEqual(records[name]['content'], name.encode())
            self.assertTrue(stat.S_ISDIR(records['lib/firmware']['fields'][1]))

    def test_missing_firmware_is_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaisesRegex(ValueError, 'missing H264 runtime'):
                pack.overlay_archive(self.seed(), Path(d))


if __name__ == '__main__':
    unittest.main()
