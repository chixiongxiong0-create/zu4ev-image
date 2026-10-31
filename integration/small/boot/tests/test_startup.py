import os
import signal
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / 'start-ibex-platform.sh'


class StartupTest(unittest.TestCase):
    def run_startup(self, profile_fail=False, handoff_fail=False, bridge_dead=False, cleanup_fail=False, iic_fail=False):
        self.assertTrue(SCRIPT.is_file(), 'missing sequential startup coordinator')
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            trace = base / 'trace'
            def executable(name, body):
                p = base / name
                p.write_text('#!/bin/sh\n' + body)
                p.chmod(0o755)
                return str(p)
            executable('start-platform.sh', f'echo bridge >> {trace}\necho $$ > {base}/bridge.pid\n' + ('exit 0\n' if bridge_dead else 'exec sleep 30\n'))
            executable('isp-tnr-startup.sh',
                       f'while [ ! -f {base}/bridge.pid ]; do sleep 0.01; done\n'
                       + ('sleep 0.05\n' if bridge_dead else '')
                       + f'echo profile >> {trace}\nexit {int(profile_fail)}\n')
            handoff = executable('ibex_isp_handoff', f'echo "handoff $*" >> {trace}\n'
                                 + ('[ "$1" != start ] || exit 1\n' if handoff_fail else '')
                                 + ('[ "$1" != stop ] || exit 1\n' if cleanup_fail else '')
                                 + 'exit 0\n')
            iic = executable('ibex_iic_prepare', f'echo iic >> {trace}\nexit {int(iic_fail)}\n')
            script = SCRIPT.read_text().replace('/tmp/', str(base) + '/').replace('/opt/sc130', str(base)).replace('/usr/bin/ibex_isp_handoff', handoff).replace('/usr/bin/ibex_iic_prepare', iic)
            path = base / 'coordinator.sh'
            path.write_text(script)
            process = subprocess.Popen(['sh', str(path)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                       text=True, start_new_session=True)
            try:
                output, _ = process.communicate(timeout=5)
            finally:
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
            return process.returncode, trace.read_text(), output

    def test_profile_finishes_before_single_handoff(self):
        code, trace, output = self.run_startup()
        self.assertEqual(code, 0, output)
        self.assertLess(trace.index('profile'), trace.index('handoff start'))
        self.assertEqual(trace.count('handoff start --ps-writers-stopped'), 1)
        self.assertLess(trace.index('profile'), trace.index('iic'))
        self.assertLess(trace.index('iic'), trace.index('handoff start'))
        self.assertIn('IBEX_STARTUP_OK', output)

    def test_profile_failure_never_starts_ibex(self):
        code, trace, output = self.run_startup(profile_fail=True)
        self.assertEqual(code, 1)
        self.assertNotIn('handoff start', trace)
        self.assertIn('IBEX_STARTUP_FAILED', output)

    def test_dead_bridge_never_starts_ibex(self):
        code, trace, output = self.run_startup(bridge_dead=True)
        self.assertEqual(code, 1)
        self.assertNotIn('handoff start', trace)
        self.assertIn('bridge exited', output)

    def test_failed_handoff_stops_once_and_does_not_retry(self):
        code, trace, output = self.run_startup(handoff_fail=True)
        self.assertEqual(code, 1)
        self.assertEqual(trace.count('handoff start'), 1)
        self.assertEqual(trace.count('handoff stop'), 1)
        self.assertLess(trace.index('handoff start'), trace.index('handoff stop'))
        self.assertIn('IBEX_STARTUP_FAILED', output)

    def test_failed_cleanup_is_reported_without_forcing_ownership(self):
        code, trace, output = self.run_startup(handoff_fail=True, cleanup_fail=True)
        self.assertEqual(code, 1)
        self.assertEqual(trace.count('handoff start'), 1)
        self.assertIn('IBEX_STOP_INCOMPLETE', output)

    def test_iic_preparation_failure_never_starts_ibex(self):
        code, trace, output = self.run_startup(iic_fail=True)
        self.assertEqual(code, 1)
        self.assertNotIn('handoff start', trace)
        self.assertIn('IIC preparation failed', output)


if __name__ == '__main__':
    unittest.main()
