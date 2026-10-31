"""Reproduce/check the fixed sigma_r=64, 8-bit bilateral range constants."""
import argparse
import hashlib
import math
from pathlib import Path


def source(sigma=64):
    header=f'// round(255*exp(-difference^2/(2*{sigma}^2))); remaining entries are zero.\n'
    lines=[]
    for difference in range(1024):
        weight=math.floor(255*math.exp(-difference*difference/(2*sigma*sigma))+.5)
        if weight:
            lines.append(f"10'd{difference}: range_weight=8'd{weight};\n")
    return header+''.join(lines)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check',action='store_true')
    args=parser.parse_args()
    for sigma,name in [(64,'range_lut.svh'),(32,'range_lut32.svh'),(128,'range_lut128.svh')]:
        path=Path(__file__).with_name(name)
        expected=source(sigma)
        if args.check:
            assert path.read_text()==expected, 'Range LUT differs from fixed formula'
        else:
            path.write_text(expected)
        print(f'RANGE_LUT_PASS sigma={sigma} sha256='+hashlib.sha256(expected.encode()).hexdigest())
