#!/usr/bin/env python3
"""Generate a smooth-field RAW10 map from validated hardware cell sums."""
import argparse, hashlib, json
from pathlib import Path
import numpy as np

def read_stats(path):
    words=Path(path).read_text().split()
    if len(words)<6 or words[0]!='FFC_STATS1': raise ValueError('invalid statistics header')
    w,h,step,frames,samples=map(int,words[1:6])
    if (w,h,step,frames,samples)!=(1280,1024,32,32,32768): raise ValueError('statistics geometry/count mismatch')
    values=np.array([int(v) for v in words[6:]],dtype=np.float64)
    if len(values)!=1280 or np.any(values<0) or np.any(values>1023*samples): raise ValueError('invalid cell sums')
    return values.reshape(32,40)/samples

def nodes(cells):
    # Measurements are cell-centred (pixel15.5,47.5,...); hardware nodes are at
    # 0,32,...,1280. Constant edge extension avoids unmeasured extrapolation.
    xs=np.arange(40)*32+15.5;ys=np.arange(32)*32+15.5
    horizontal=np.array([np.interp(np.arange(41)*32,xs,row) for row in cells])
    return np.array([np.interp(np.arange(33)*32,ys,col) for col in horizontal.T]).T

def make_map(dark,flat=None):
    if not np.isfinite(dark).all() or dark.mean()>200 or dark.max()-dark.min()>150:
        raise ValueError('dark field is implausible; check cover, gain and exposure')
    gain=np.ones_like(dark)
    if flat is not None:
        signal=flat-dark
        if flat.max()>=1000 or signal.min()<64: raise ValueError('flat saturated or insufficient signal')
        gain=np.median(signal)/signal
        if gain.min()<.5 or gain.max()>2: raise ValueError('flat gain outside calibrated 0.5..2x range')
    dn=np.floor(nodes(dark)+.5).astype(np.uint32)
    gn=np.floor(nodes(gain)*4096+.5).astype(np.uint32)
    return (gn<<10)|dn

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--dark',type=Path,required=True);p.add_argument('--flat',type=Path)
    p.add_argument('--output',type=Path,required=True);p.add_argument('--report',type=Path,required=True)
    a=p.parse_args();dark=read_stats(a.dark);flat=read_stats(a.flat) if a.flat else None
    packed=make_map(dark,flat)
    text='FFC_MAP1 1280 1024 52\n'+''.join(f'{int(v):06x}\n' for v in packed.flat)
    report={'kind':'dark-and-flat' if a.flat else 'dark-only-unity-gain',
      'dark_mean_raw10':float(dark.mean()),'dark_cell_min_raw10':float(dark.min()),
      'dark_cell_max_raw10':float(dark.max()),'dark_cell_std_raw10':float(dark.std()),
      'pedestal':52,'map_sha256':hashlib.sha256(text.encode()).hexdigest(),
      'dark_sha256':hashlib.sha256(a.dark.read_bytes()).hexdigest(),
      'flat_sha256':hashlib.sha256(a.flat.read_bytes()).hexdigest() if a.flat else None,
      'scope':'smooth spatial field; not per-pixel PRNU/DSNU or hot-pixel correction',
      'conditions':'valid only for recorded sensor exposure, gain and temperature; retain matching acquisition metadata'}
    a.output.write_bytes(text.encode('ascii'));a.report.write_bytes((json.dumps(report,indent=2)+'\n').encode('utf-8'))
    print(json.dumps(report,indent=2))
if __name__=='__main__':main()
