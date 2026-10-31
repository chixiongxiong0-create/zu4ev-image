#!/usr/bin/env python3
"""Import the complete, pinned OpenTitan tree, preserving upstream licenses."""
import argparse
import io
from pathlib import Path
import urllib.request
import zipfile

REVISION = "8e7f977585b8e8304feaf688d7e8429059bfd097"
URL = f"https://codeload.github.com/lowRISC/opentitan/zip/{REVISION}"

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--destination", type=Path, default=Path(__file__).parent / "vendor")
    args = parser.parse_args()
    destination = args.destination.resolve()
    if destination.exists():
        raise SystemExit(f"Refusing to overwrite existing destination: {destination}")
    with urllib.request.urlopen(URL, timeout=180) as response:
        archive = zipfile.ZipFile(io.BytesIO(response.read()))
    prefix = f"opentitan-{REVISION}/"
    # Validate the entire archive before creating any output.
    for item in archive.infolist():
        if not item.filename.startswith(prefix):
            raise SystemExit("Unexpected archive root")
        relative = Path(item.filename[len(prefix):])
        if relative.is_absolute() or ".." in relative.parts:
            raise SystemExit("Unsafe archive path")
    destination.mkdir(parents=True)
    for item in archive.infolist():
        relative = item.filename[len(prefix):]
        if not relative:
            continue
        target = destination / relative
        if item.is_dir():
            target.mkdir(parents=True, exist_ok=True)
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(archive.read(item))
    (destination / "IMPORTED_REVISION").write_text(REVISION + "\n", encoding="ascii")
    from prepare_metadata import prepare
    prepare(destination)
    print(f"Imported OpenTitan {REVISION} into {destination}")

if __name__ == "__main__":
    main()
