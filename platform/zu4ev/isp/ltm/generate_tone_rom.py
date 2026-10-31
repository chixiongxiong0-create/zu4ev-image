"""Generate a 10-bit base curve, preserving the original piecewise knots."""
from fractions import Fraction
from pathlib import Path
import hashlib
import json

X=(0,1,4,10,25,50,75,90,100)
Y=(16,22,49,82,128,176,208,224,235)


def values():
    result=[]
    for code in range(1024):
        x=Fraction(min(code,971)*100,971)
        segment=next((i for i in range(8) if x<=X[i+1]),7)
        y=Y[segment]+(x-X[segment])*Fraction(Y[segment+1]-Y[segment],X[segment+1]-X[segment])
        mapped=(y-16)*Fraction(1023,219)
        result.append((mapped.numerator*2+mapped.denominator)//(2*mapped.denominator))
    return result


if __name__=='__main__':
    root=Path(__file__).resolve().parent
    lut=values()
    assert lut[0]==0 and lut[971]==1023 and all(a<=b for a,b in zip(lut,lut[1:]))
    coe='memory_initialization_radix=10;\nmemory_initialization_vector=\n'+',\n'.join(map(str,lut))+';\n'
    (root/'base_tone.coe').write_text(coe)
    config=dict(black_level=52,white_corrected=971,output_bits=10,
                input_percent_knots=X,video_y_knots=Y,
                sha256=hashlib.sha256(coe.encode()).hexdigest())
    (root/'base_tone.json').write_text(json.dumps(config,indent=2)+'\n')
    print('TONE_ROM_GENERATED entries=1024 black=52 white=971 sha256='+config['sha256'])
