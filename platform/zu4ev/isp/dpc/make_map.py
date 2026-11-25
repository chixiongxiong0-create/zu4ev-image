#!/usr/bin/env python3
"""Build an ordered repair map from confirmed coordinates or repeated RAW surveys."""
import argparse
import hashlib
import json
import math
from pathlib import Path


def read_survey(path, width, height, persistence):
    lines = Path(path).read_text(encoding="ascii").splitlines()
    if len(lines) < 2:
        raise ValueError("truncated survey")
    tag, w, h, frames, source, mode, threshold = lines[0].split()
    if tag != "DPC_SURVEY1" or (int(w), int(h)) != (width, height):
        raise ValueError("invalid survey header/geometry")
    frames, threshold = int(frames), int(threshold)
    if source != "raw" or mode not in ("high", "low") or not 2 <= frames <= 255 or not 0 <= threshold <= 1023:
        raise ValueError("calibration requires a valid multi-frame raw survey")
    if lines[-1].split() != ["END", str(len(lines) - 2)]:
        raise ValueError("truncated or inconsistent survey footer")
    limit = math.ceil(frames * persistence)
    points, seen = set(), set()
    for line in lines[1:-1]:
        x, y, hits = map(int, line.split())
        if not 0 <= x < width or not 0 <= y < height or not 1 <= hits <= frames or (x, y) in seen:
            raise ValueError("invalid/duplicate survey record")
        seen.add((x, y))
        if hits >= limit:
            points.add((x, y))
    return points, {"frames": frames, "mode": mode, "threshold": threshold,
                    "min_hits": limit, "candidates": len(seen), "persistent": len(points)}


def make_runs(points, width, height):
    if not 2 <= width <= 2048 or width % 2 or not 1 <= height <= 1024:
        raise ValueError("unsupported geometry")
    runs = []
    for x, y in sorted(set(points), key=lambda p: (p[1], p[0])):
        if not 0 <= x < width or not 0 <= y < height:
            raise ValueError(f"out-of-image defect ({x},{y})")
        if runs and y == runs[-1][1] and x == runs[-1][0] + runs[-1][2]:
            start, _, length = runs.pop()
            runs.append((start, y, length + 1))
        else:
            runs.append((x, y, 1))
    for x, y, length in runs:
        if length > 32 or length == width:
            raise ValueError(f"unrepairable horizontal run at ({x},{y}), length {length}")
    if len(runs) > 1024:
        raise ValueError("map exceeds 1024 runs")
    return runs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--survey", type=Path, action="append", default=[])
    parser.add_argument("--coordinates", type=Path, action="append", default=[],
                        help="confirmed x y per line; # starts a comment")
    parser.add_argument("--min-persistence", type=float, default=0.95)
    parser.add_argument("--require-all-surveys", action="store_true",
                        help="keep only points persistent in every supplied survey")
    parser.add_argument("--width", type=int, default=1280)
    parser.add_argument("--height", type=int, default=1024)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    if not args.survey and not args.coordinates:
        parser.error("provide a survey or confirmed coordinates")
    if not 0.5 <= args.min_persistence <= 1:
        parser.error("persistence must be between 0.5 and 1")
    if args.require_all_surveys and len(args.survey) < 2:
        parser.error("--require-all-surveys needs at least two surveys")
    points, sources = set(), []
    survey_points = []
    for path in args.survey:
        found, details = read_survey(path, args.width, args.height, args.min_persistence)
        survey_points.append(found)
        sources.append({"path": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest(), **details})
    if survey_points:
        combine = set.intersection if args.require_all_surveys else set.union
        points.update(combine(*survey_points))
    for path in args.coordinates:
        for line in path.read_text(encoding="ascii").splitlines():
            data = line.split("#", 1)[0].strip()
            if data:
                x, y = map(int, data.split())
                points.add((x, y))
        sources.append({"path": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                        "kind": "supplied-confirmed-coordinates"})
    runs = make_runs(points, args.width, args.height)
    text = f"DPC_MAP1 {args.width} {args.height} {len(runs)}\n" + "".join(
        f"{x} {y} {n}\n" for x, y, n in runs)
    data = text.encode("ascii")
    args.output.write_bytes(data)
    report = {"pixels": len(points), "runs": len(runs), "longest_run": max((r[2] for r in runs), default=0),
              "map_sha256": hashlib.sha256(data).hexdigest(), "sources": sources,
              "survey_combination": "intersection" if args.require_all_surveys else "union",
              "conditions": "Only use surveys taken under verified dark or uniform flat illumination."}
    args.report.write_bytes((json.dumps(report, indent=2) + "\n").encode("utf-8"))
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
