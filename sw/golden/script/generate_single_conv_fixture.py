#!/usr/bin/env python3
"""Generate the deterministic Phase 1 single-convolution fixture."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from sw.golden.model.conv2d_int8_reference import (  # noqa: E402
    compute_accumulator,
    sha256_file,
    write_values,
)


DEFAULT_CONFIG = {
    "fixture_id": "single_conv_001",
    "layout": "CHW",
    "input_shape": [1, 5, 5],
    "output_shape": [1, 3, 3],
    "kernel_shape": [1, 1, 3, 3],
    "stride": 1,
    "padding": 0,
    "input_dtype": "int8",
    "weight_dtype": "int8",
    "bias_dtype": "int32",
    "acc_dtype": "int32",
    "output_dtype": "int8",
    "input_zero_point": 0,
    "weight_zero_point": 0,
    "output_zero_point": 0,
    "compare_target_phase_1": "expected_acc_int32",
    "endianness": "little",
}


INPUT_INT8 = [
    -3,
    1,
    4,
    0,
    2,
    5,
    -2,
    7,
    3,
    -1,
    6,
    0,
    -4,
    8,
    2,
    -5,
    9,
    1,
    -6,
    4,
    3,
    -7,
    2,
    5,
    -8,
]


WEIGHT_INT8 = [
    2,
    -1,
    0,
    3,
    1,
    -2,
    -1,
    4,
    2,
]


BIAS_INT32 = [7]


def write_config(path: Path, config: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(config, indent=2) + "\n", encoding="ascii")


def generate_fixture(fixture_id: str, fixtures_root: Path) -> Path:
    if fixture_id != DEFAULT_CONFIG["fixture_id"]:
        raise ValueError("Phase 1 currently supports only single_conv_001")

    fixture_dir = fixtures_root / fixture_id
    fixture_dir.mkdir(parents=True, exist_ok=True)

    config = dict(DEFAULT_CONFIG)
    write_config(fixture_dir / "layer_config.json", config)
    write_values(fixture_dir / "input_int8.hex", INPUT_INT8)
    write_values(fixture_dir / "weight_int8.hex", WEIGHT_INT8)
    write_values(fixture_dir / "bias_int32.hex", BIAS_INT32)

    acc_values = compute_accumulator(config, INPUT_INT8, WEIGHT_INT8, BIAS_INT32)
    write_values(fixture_dir / "expected_acc_int32.hex", acc_values)

    return fixture_dir


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture", default="single_conv_001", help="Fixture id to write")
    parser.add_argument(
        "--fixtures-root",
        default=str(REPO_ROOT / "sw" / "fixture"),
        help="Directory that contains fixture subdirectories",
    )
    args = parser.parse_args()

    fixture_dir = generate_fixture(args.fixture, Path(args.fixtures_root))
    expected_path = fixture_dir / "expected_acc_int32.hex"
    print(f"fixture: {args.fixture}")
    print(f"wrote: {fixture_dir}")
    print(f"expected_acc_int32_sha256: {sha256_file(expected_path)}")
    print("PASS: deterministic fixture generated")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
