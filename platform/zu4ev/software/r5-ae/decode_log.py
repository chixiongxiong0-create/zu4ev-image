"""Decode non-invasive XSDB dumps of the R5 auto exposure ring."""
import argparse
import json
import statistics
import struct
from pathlib import Path

FIELDS = (
    "fe_seq stats_seq stats_frame mean current_exposure current_gain "
    "sof_frame_before sof_frame_after proposed_code change_kind irq_tick "
    "iic_start_tick high_end_tick low_end_tick fe_to_sof_pl_cycles iic_hz fault"
).split()
R5_HZ = 525_000_000
VIDEO_HZ = 200_000_000


def words(path):
    data = path.read_bytes()
    if len(data) % 4:
        raise ValueError(f"{path}: length is not a multiple of four")
    return struct.unpack("<" + "I" * (len(data) // 4), data)


def delta(a, b):
    return ((b - a) & 0xFFFFFFFF) / R5_HZ * 1_000_000


def decode(directory):
    before = words(directory / "ae_log_before.bin")
    after = words(directory / "ae_log_after.bin")
    raw = words(directory / "ae_records.bin")
    if len(before) != 8 or len(after) != 8 or len(raw) != 512 * len(FIELDS):
        raise ValueError("Unexpected dump size")
    if before[0] != 0x41453552 or after[0] != before[0]:
        raise ValueError("R5 AE magic is absent")
    slots = [dict(zip(FIELDS, raw[i:i + len(FIELDS)]))
             for i in range(0, len(raw), len(FIELDS))]
    count = min(before[2], 512)
    start = (before[2] - count) % 512
    records = [slots[(start + i) % 512] for i in range(count)]
    records = [r for r in records if r["fe_seq"] and r["stats_seq"]]
    for r in records:
        if r["change_kind"]:
            r["irq_to_iic_us"] = round(delta(r["irq_tick"], r["iic_start_tick"]), 3)
            r["iic_write_us"] = round(delta(r["iic_start_tick"], r["low_end_tick"]), 3)
            r["fe_to_axi_sof_us"] = round(r["fe_to_sof_pl_cycles"] / VIDEO_HZ * 1e6, 3)
    changes = [r for r in records if r["change_kind"] and not r["fault"]]
    summary = {
        "log_before": dict(zip(("magic", "version", "write_index", "fault",
                                "irq_count", "last_fe_seq", "iic_hz", "dropped_fe"), before)),
        "log_after": dict(zip(("magic", "version", "write_index", "fault",
                               "irq_count", "last_fe_seq", "iic_hz", "dropped_fe"), after)),
        "record_count": len(records),
        "change_count": len(changes),
        "exposure_write_count": sum(r["change_kind"] == 1 for r in changes),
        "gain_write_count": sum(r["change_kind"] == 2 for r in changes),
        "mean_first": records[0]["mean"] if records else None,
        "mean_last": records[-1]["mean"] if records else None,
        "mean_last_30": round(statistics.mean(r["mean"] for r in records[-30:]), 2)
        if records else None,
        "max_irq_to_iic_us": max((r["irq_to_iic_us"] for r in changes), default=None),
        "max_iic_write_us": max((r["iic_write_us"] for r in changes), default=None),
        "cross_frame_writes": sum(r["sof_frame_after"] != r["sof_frame_before"]
                                  for r in changes),
    }
    return {"summary": summary, "records": records}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("dump_dir", type=Path)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    result = decode(args.dump_dir)
    print(json.dumps(result["summary"], indent=2))
    if args.out:
        args.out.write_text(json.dumps(result, indent=2), encoding="utf-8")
