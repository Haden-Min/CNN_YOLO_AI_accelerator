#!/usr/bin/env python3
"""Compare RTL accumulator output against the Phase 1 golden fixture."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from sw.golden.model.conv2d_int8_reference import (  # noqa: E402
    dtype_range,
    load_config,
    product,
    read_values,
    validate_config,
)


DTYPE_BITS = {
    "int8": 8,
    "int32": 32,
}


def dtype_bits(dtype: str) -> int:
    try:
        return DTYPE_BITS[dtype]
    except KeyError as exc:
        raise ValueError(f"unsupported dtype: {dtype}") from exc


def parse_actual_token(token: str, dtype: str) -> int:
    bits = dtype_bits(dtype)
    hex_width = bits // 4
    unsigned_token = token.lower().removeprefix("0x")
    looks_hex = (
        token.lower().startswith("0x")
        or any(ch in unsigned_token for ch in "abcdef")
        or (len(unsigned_token) == hex_width and all(ch in "0123456789abcdef" for ch in unsigned_token))
    )

    if token.startswith(("-", "+")) or not looks_hex:
        value = int(token, 0)
    else:
        raw = int(unsigned_token, 16)
        if raw >= 2 ** (bits - 1):
            raw -= 2**bits
        value = raw

    lo, hi = dtype_range(dtype)
    if value < lo or value > hi:
        raise ValueError(f"{value} outside {dtype} range [{lo}, {hi}]")
    return value


def read_actual_values(path: Path, dtype: str, expected_count: int) -> list[int]:
    values: list[int] = []
    with path.open("r", encoding="ascii") as f:
        for line_no, raw_line in enumerate(f, start=1):
            line = raw_line.split("#", 1)[0].strip()
            if not line:
                continue
            for token in line.replace(",", " ").split():
                try:
                    values.append(parse_actual_token(token, dtype))
                except ValueError as exc:
                    raise ValueError(f"{path}:{line_no}: {exc}") from exc

    if len(values) != expected_count:
        raise ValueError(f"{path}: expected {expected_count} values, found {len(values)}")
    return values


def index_to_coord(index: int, output_shape: list[int]) -> tuple[int, int, int]:
    _, output_h, output_w = output_shape
    plane = output_h * output_w
    oc = index // plane
    rem = index % plane
    oh = rem // output_w
    ow = rem % output_w
    return oc, oh, ow


def compare_values(
    expected: list[int], actual: list[int], output_shape: list[int], max_report: int
) -> int:
    mismatch_count = 0
    for index, (expected_value, actual_value) in enumerate(zip(expected, actual)):
        if expected_value == actual_value:
            continue
        mismatch_count += 1
        if mismatch_count <= max_report:
            oc, oh, ow = index_to_coord(index, output_shape)
            delta = actual_value - expected_value
            print(
                "mismatch "
                f"flat_index={index} oc={oc} oh={oh} ow={ow} "
                f"expected={expected_value} actual={actual_value} delta={delta}"
            )
    return mismatch_count


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture", required=True, help="Path to a fixture directory")
    parser.add_argument(
        "--actual",
        help=(
            "Path to actual RTL accumulator output. Defaults to "
            "sw/fixture/generated/<fixture_id>/actual_acc_int32.hex"
        ),
    )
    parser.add_argument("--max-report", type=int, default=16)
    args = parser.parse_args()

    fixture_dir = Path(args.fixture)
    config = load_config(fixture_dir)
    output_shape = validate_config(config)
    expected_count = product(output_shape)
    expected_path = fixture_dir / "expected_acc_int32.hex"

    actual_path = (
        Path(args.actual)
        if args.actual
        else REPO_ROOT
        / "sw"
        / "fixture"
        / "generated"
        / config["fixture_id"]
        / "actual_acc_int32.hex"
    )

    expected = read_values(expected_path, config["acc_dtype"], expected_count)
    actual = read_actual_values(actual_path, config["acc_dtype"], expected_count)
    mismatch_count = compare_values(expected, actual, output_shape, args.max_report)

    print(f"Compared values: {expected_count}")
    print(f"Mismatch count: {mismatch_count}")
    if mismatch_count == 0:
        print("PASS")
        return 0
    print("FAIL")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
