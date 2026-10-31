"""Produce a complete little-endian 256 KiB ROM image for readmemh."""
import pathlib
import sys
data = pathlib.Path(sys.argv[1]).read_bytes()
if len(data) > 256 * 1024:
    raise SystemExit("ROM image exceeds 256 KiB")
data = data.ljust(256 * 1024, b'\x00')
pathlib.Path(sys.argv[2]).write_text(''.join(
    f'{int.from_bytes(data[i:i+4], "little"):08x}\n'
    for i in range(0, len(data), 4)))
