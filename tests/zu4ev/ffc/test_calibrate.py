import importlib.util, pathlib, unittest, tempfile, subprocess, sys, hashlib, json
import numpy as np
p=pathlib.Path(__file__).resolve().parents[3]/'platform/zu4ev/isp/ffc/calibrate.py'
s=importlib.util.spec_from_file_location('calibrate',p);m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
class Calibration(unittest.TestCase):
 def test_uniform_dark(self):
  packed=m.make_map(np.full((32,40),52.25))
  self.assertEqual(packed.shape,(33,41));self.assertTrue(np.all(packed==((4096<<10)|52)))
 def test_flat_inverse(self):
  dark=np.full((32,40),52.)
  signal=np.tile(np.linspace(300,600,40),(32,1))
  packed=m.make_map(dark,dark+signal)
  self.assertTrue(np.all((packed&1023)==52))
  self.assertGreater((packed[0,0]>>10),(packed[0,-1]>>10))
 def test_bad_data(self):
  with self.assertRaises(ValueError):m.make_map(np.full((32,40),500.))
  with self.assertRaises(ValueError):m.make_map(np.full((32,40),52.),np.full((32,40),1023.))
  with self.assertRaises(ValueError):m.make_map(np.full((32,40),52.),np.full((32,40),60.))
 def test_cli_hash(self):
  with tempfile.TemporaryDirectory() as directory:
   root=pathlib.Path(directory);dark=root/'dark.stats';out=root/'dark.map';report=root/'dark.json'
   dark.write_text('FFC_STATS1 1280 1024 32 32 32768\n'+(str(52*32768)+'\n')*1280)
   subprocess.run([sys.executable,str(p),'--dark',str(dark),'--output',str(out),'--report',str(report)],check=True,stdout=subprocess.DEVNULL)
   self.assertEqual(json.loads(report.read_text())['map_sha256'],hashlib.sha256(out.read_bytes()).hexdigest())
   self.assertEqual(len(out.read_text().split()),4+1353)
 def test_edges(self):
  cells=np.tile(np.arange(40),(32,1));n=m.nodes(cells)
  self.assertEqual(n[0,0],0);self.assertEqual(n[-1,-1],39)
  self.assertAlmostEqual(n[10,10],(320-15.5)/32)
if __name__=='__main__':unittest.main()
