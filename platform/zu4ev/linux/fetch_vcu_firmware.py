#!/usr/bin/env python3
"""Fetch pinned AMD 2019.2 firmware; preserve its redistribution license."""
import argparse
import base64
import hashlib
import json
import time
from pathlib import Path
import urllib.request

REV = '29ab982965b797b1c9b567faba47378578398f4a'
FILES = {'al5e_b.fw': ('1.0.0/lib/firmware/al5e_b.fw', 14680),
         'al5e.fw': ('1.0.0/lib/firmware/al5e.fw', 126572),
         'LICENSE': ('LICENSE', None)}
HASHES = {'al5e_b.fw': '6a0d5efefebf75a2f5cb5a9168a16090c1cc6cade7f0c6b995ee95c4c21c131a',
          'al5e.fw': '0f054422272cf8dd94a4b32781cbbdf31c034619a2f7790f25ecdb50885f6caf'}

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    manifest = {'repository': 'https://github.com/Xilinx/vcu-firmware',
                'revision': REV, 'files': {}}
    for name, (source, size) in FILES.items():
        url = f'https://api.github.com/repos/Xilinx/vcu-firmware/contents/{source}?ref={REV}'
        request = urllib.request.Request(url, headers={'User-Agent': 'sc130-vcu-build'})
        for attempt in range(5):
            try:
                with urllib.request.urlopen(request, timeout=60) as response:
                    obj = json.load(response)
                break
            except OSError:
                if attempt == 4:
                    raise
                time.sleep(1 + attempt)
        data = base64.b64decode(obj['content'])
        if size is not None and len(data) != size:
            raise ValueError(f'Unexpected firmware size: {name}: {len(data)}')
        digest = hashlib.sha256(data).hexdigest()
        if name in HASHES and digest != HASHES[name]:
            raise ValueError(f'Unexpected firmware SHA256: {name}')
        (args.output / name).write_bytes(data)
        manifest['files'][name] = {'bytes': len(data), 'sha256': digest}
    (args.output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')

if __name__ == '__main__':
    main()
