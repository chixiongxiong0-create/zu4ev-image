import gzip
import importlib.util
import stat
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / 'package_ibex_qspi.py'


def record(name, payload=b'', mode=stat.S_IFREG | 0o644, rdev=(0, 0)):
    name = name.encode() + b'\0'
    fields = [1, mode, 0, 0, 1, 0, len(payload), 0, 0, *rdev, len(name), 0]
    raw = b'070701' + b''.join(f'{n:08x}'.encode() for n in fields) + name
    raw += bytes(-len(raw) % 4)
    raw += payload
    return raw + bytes(-len(raw) % 4)


class PackageTest(unittest.TestCase):
    def setUp(self):
        self.assertTrue(SCRIPT.is_file(), 'missing Ibex QSPI packager')
        spec = importlib.util.spec_from_file_location('pack', SCRIPT)
        self.pack = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.pack)

    def test_overlay_preserves_second_cpio_stream_device_node(self):
        first = record('init', b'old-init', stat.S_IFREG | 0o755) + record('TRAILER!!!')
        second = record('dev/console', mode=stat.S_IFCHR | 0o600, rdev=(5, 1)) + record('TRAILER!!!')
        packed = gzip.compress(first + bytes(-len(first) % 512) + second, mtime=0)
        output = self.pack.overlay_initramfs(packed, {'init': (b'new-init', 0o755)})
        self.assertTrue(output.startswith(packed), 'original gzip members must remain byte-identical')
        records = self.pack.parse_newc_streams(gzip.decompress(output))
        self.assertEqual([e['name'] for e in records], ['init', 'dev/console', 'init'])
        self.assertEqual(records[0]['content'], b'old-init')
        self.assertEqual(records[1]['fields'][1], stat.S_IFCHR | 0o600)
        self.assertEqual(records[1]['fields'][9:11], [5, 1])
        self.assertEqual(records[-1]['content'], b'new-init')

    def test_rejects_truncated_archive_and_unsafe_overlay_path(self):
        with self.assertRaises(ValueError):
            self.pack.parse_newc_streams(record('init')[:-2])
        with self.assertRaises(ValueError):
            self.pack.overlay_initramfs(gzip.compress(record('TRAILER!!!')), {'../escape': (b'', 0o755)})

    def test_missing_console_node_is_created_with_character_device_metadata(self):
        packed=gzip.compress(record('dev',mode=stat.S_IFDIR|0o755)+record('TRAILER!!!'))
        output=self.pack.overlay_initramfs(packed,{}, {'dev/console': (0o600,5,1)})
        final={e['name']:e for e in self.pack.parse_newc_streams(gzip.decompress(output))}
        self.assertEqual(final['dev/console']['fields'][1],stat.S_IFCHR|0o600)
        self.assertEqual(final['dev/console']['fields'][9:11],[5,1])

    def test_device_conflicts_are_rejected_and_correct_existing_nodes_preserved(self):
        good=self.pack.parse_newc_streams(record('dev/console',mode=stat.S_IFCHR|0o600,rdev=(5,1))+record('TRAILER!!!'))
        additions=self.pack.device_additions({e['name']:e for e in good})
        self.assertNotIn('dev/console',additions)
        self.assertNotIn('dev/ttyPS0',additions)
        bad=self.pack.parse_newc_streams(record('dev/console')+record('TRAILER!!!'))
        with self.assertRaises(ValueError):
            self.pack.device_additions({e['name']:e for e in bad})
        packed=gzip.compress(record('dev',mode=stat.S_IFDIR|0o755)+record('TRAILER!!!'))
        with self.assertRaises(ValueError):
            self.pack.overlay_initramfs(packed,{'dev/console':(b'',0o600)},{'dev/console':(0o600,5,1)})

    def test_init_has_one_coordinator_and_no_parallel_ps_profile(self):
        original = (b'#!/bin/sh\nmount -t proc proc /proc\n'
                    b'/opt/sc130/start-platform.sh >/tmp/sc130-platform.log 2>&1 &\n'
                    b'/opt/sc130/isp-tnr-startup.sh >/tmp/isp-tnr-startup.log 2>&1 &\n'
                    b'while true; do /bin/sh; done\n')
        patched = self.pack.patch_init(original)
        self.assertEqual(patched.count(b'/opt/sc130/start-ibex-platform.sh'), 1)
        self.assertNotIn(b'/opt/sc130/isp-tnr-startup.sh', patched)
        self.assertNotIn(b'/opt/sc130/start-platform.sh', patched)
        self.assertIn(b'mount -t proc proc /proc', patched)
        self.assertIn(b'while true; do /bin/sh; done', patched)
        with self.assertRaises(ValueError):
            self.pack.patch_init(patched)

    def test_flash_layout_limits(self):
        self.assertEqual(self.pack.validate_sizes(12 * 2**20, 20 * 2**20), 32 * 2**20)
        for boot, fit in [(0, 1), (12 * 2**20 + 1, 1), (1, 0), (1, 20 * 2**20 + 1)]:
            with self.assertRaises(ValueError):
                self.pack.validate_sizes(boot, fit)


if __name__ == '__main__':
    unittest.main()
