#!/usr/bin/env python3
"""Narrow obsolete TL-UL aggregate dependencies without modifying upstream RTL.

The pinned peripheral metadata references deprecated lowrisc:ip:tlul, which also
pulls unrelated DMI/JTAG debug cores and obsolete waiver schema. Each peripheral
actually needs adapter_reg and adapter_reg_racl; use their declared transitive
dependencies instead. This operation is deterministic and idempotent.
"""
import argparse
from pathlib import Path


def prepare(vendor):
    paths = ["hw/ip/rv_timer/rv_timer.core", "hw/ip/i2c/i2c.core",
             "hw/ip/uart/uart.core", "hw/top_earlgrey/ip_autogen/gpio/gpio.core"]
    for relative in paths:
        path = vendor / relative
        text = path.read_text(encoding="utf-8")
        old = "      - lowrisc:ip:tlul"
        new = "      - lowrisc:tlul:adapter_reg_racl"
        if old in text:
            path.write_text(text.replace(old, new), encoding="utf-8")
        elif new not in text:
            raise RuntimeError(f"Unexpected upstream dependency metadata: {path}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vendor", type=Path,
                        default=Path(__file__).resolve().parent / "vendor")
    prepare(parser.parse_args().vendor)
