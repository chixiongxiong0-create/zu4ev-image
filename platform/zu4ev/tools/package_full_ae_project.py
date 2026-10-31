"""Prepare an immutable-source bundle; never execute Vivado or build software."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
from datetime import datetime, timezone

SOURCE_SUFFIXES = {'.v', '.sv', '.vh', '.svh', '.tcl', '.xdc', '.coe', '.mem',
                   '.json', '.md', '.py', '.c', '.h', '.sh'}
EXCLUDED_DIRS = {'vendor', '__pycache__', '.git', '.Xil', '.cache', 'node_modules',
                 'build', 'reports', 'dist', 'xsim.dir'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--destination', type=Path, help='Default: SOURCE/build/full_ae')
    args = parser.parse_args()
    source = args.source.resolve()
    destination = (args.destination or source / 'build/full_ae').resolve()
    if destination.exists():
        parser.error(f'destination already exists: {destination}')
    roots = ['rtl', 'isp', 'hardware', 'constraints',
             'software/isp-control', 'software/tnr-control']
    selected = []
    for folder in roots:
        directory = source / folder
        if not directory.is_dir():
            parser.error(f'missing source directory: {directory}')
        for path in directory.rglob('*'):
            relative = path.relative_to(source)
            if any(part in EXCLUDED_DIRS for part in relative.parts):
                continue
            if path.is_file() and (path.suffix.lower() in SOURCE_SUFFIXES or path.name == 'Makefile'):
                if path.is_symlink():
                    parser.error(f'symlink source is not supported: {path}')
                selected.append(relative)
    selected += [Path('tools/create_full_ae_project.tcl'),
                 Path('tools/add_hierarchy_sources.tcl'),
                 Path('tools/package_full_ae_project.py'),
                 Path('docs/full_ae_project.md')]
    selected += [p.relative_to(source) for p in source.glob('README*') if p.is_file()]
    for relative in selected:
        if not (source / relative).is_file():
            parser.error(f'missing source: {relative}')
    destination.mkdir(parents=True, exist_ok=False)
    entries = []
    for relative in sorted(set(selected)):
        original = source / relative
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        # Capture bytes once so the manifest describes exactly the saved source.
        content = original.read_bytes()
        target.write_bytes(content)
        shutil.copystat(original, target)
        digest = hashlib.sha256(content).hexdigest()
        entries.append({'path': relative.as_posix(), 'original_path': str(original),
                        'source_sha256': digest, 'snapshot_sha256': digest,
                        'bytes': len(content)})
    manifest = {'format': 1, 'created_utc': datetime.now(timezone.utc).isoformat(),
                'source_root': str(source), 'bundle_root_at_creation': str(destination),
                'scope': 'Source snapshot only; no tools or builds executed',
                'files': entries}
    (destination / 'source_manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    (destination / 'BUNDLE_README.md').write_text(
        '# Camera + RAW10 statistics project\n\n'
        'Read docs/full_ae_project.md for generation-only instructions.\n'
        'Sources are unchanged snapshots; source_manifest.json records SHA-256 values.\n'
        'The project is generated at project/camera.xpr. No firmware is included.\n', encoding='utf-8')
    print(f'Source bundle prepared: {destination}')


if __name__ == '__main__':
    main()
