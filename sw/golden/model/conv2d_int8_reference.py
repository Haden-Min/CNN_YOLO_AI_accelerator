#!/usr/bin/env python3
"""Bit-exact INT8 convolution reference for deterministic fixtures."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Iterable


SIGNED_RANGES = {
    "int8": (-(2**7), 2**7 - 1),
    "int32": (-(2**31), 2**31 - 1),
}


def load_config(fixture_dir: Path) -> dict:
    config_path = fixture_dir / "layer_config.json"
    if not config_path.exists():
        raise FileNotFoundError(f"missing layer config: {config_path}")
    with config_path.open("r", encoding="ascii") as f:
        return json.load(f)


def product(values: Iterable[int]) -> int:
    result = 1
    for value in values:
        result *= int(value)
    return result


def dtype_range(dtype: str) -> tuple[int, int]:
    try:
        return SIGNED_RANGES[dtype]
    except KeyError as exc:
        raise ValueError(f"unsupported dtype: {dtype}") from exc


def read_values(path: Path, dtype: str, expected_count: int | None = None) -> list[int]:
    lo, hi = dtype_range(dtype)
    values: list[int] = []
    with path.open("r", encoding="ascii") as f:
        for line_no, raw_line in enumerate(f, start=1):
            line = raw_line.split("#", 1)[0].strip()
            if not line:
                continue
            for token in line.replace(",", " ").split():
                value = int(token, 0)
                if value < lo or value > hi:
                    raise ValueError(
                        f"{path}:{line_no}: {value} outside {dtype} range [{lo}, {hi}]"
                    )
                values.append(value)

    if expected_count is not None and len(values) != expected_count:
        raise ValueError(
            f"{path}: expected {expected_count} values, found {len(values)}"
        )
    return values


def write_values(path: Path, values: Iterable[int]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    data = "".join(f"{int(value)}\n" for value in values)
    path.write_text(data, encoding="ascii")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def compute_output_shape(config: dict) -> list[int]:
    if config["layout"] != "CHW":
        raise ValueError(f"unsupported layout: {config['layout']}")

    ic, h, w = [int(x) for x in config["input_shape"]]
    oc, weight_ic, kh, kw = [int(x) for x in config["kernel_shape"]]
    stride = int(config["stride"])
    padding = int(config["padding"])

    if ic != weight_ic:
        raise ValueError(f"input channels {ic} != weight channels {weight_ic}")
    if stride <= 0:
        raise ValueError("stride must be positive")
    if padding < 0:
        raise ValueError("padding must be non-negative")

    out_h_numer = h + 2 * padding - kh
    out_w_numer = w + 2 * padding - kw
    if out_h_numer < 0 or out_w_numer < 0:
        raise ValueError("kernel is larger than padded input")
    if out_h_numer % stride != 0 or out_w_numer % stride != 0:
        raise ValueError("configured stride does not produce integer output shape")

    return [oc, out_h_numer // stride + 1, out_w_numer // stride + 1]


def validate_config(config: dict) -> list[int]:
    required = [
        "fixture_id",
        "layout",
        "input_shape",
        "output_shape",
        "kernel_shape",
        "stride",
        "padding",
        "input_dtype",
        "weight_dtype",
        "bias_dtype",
        "acc_dtype",
    ]
    missing = [key for key in required if key not in config]
    if missing:
        raise ValueError(f"missing config keys: {', '.join(missing)}")

    computed = compute_output_shape(config)
    configured = [int(x) for x in config["output_shape"]]
    if computed != configured:
        raise ValueError(
            f"output_shape mismatch: config has {configured}, computed {computed}"
        )
    return computed


def input_index(ic: int, h: int, w: int, height: int, width: int) -> int:
    return ic * height * width + h * width + w


def weight_index(
    oc: int,
    ic: int,
    kh: int,
    kw: int,
    input_channels: int,
    kernel_h: int,
    kernel_w: int,
) -> int:
    return (
        oc * input_channels * kernel_h * kernel_w
        + ic * kernel_h * kernel_w
        + kh * kernel_w
        + kw
    )


def compute_accumulator(
    config: dict, input_values: list[int], weight_values: list[int], bias_values: list[int]
) -> list[int]:
    output_shape = validate_config(config)
    input_channels, input_h, input_w = [int(x) for x in config["input_shape"]]
    output_channels, output_h, output_w = output_shape
    _, weight_channels, kernel_h, kernel_w = [int(x) for x in config["kernel_shape"]]
    stride = int(config["stride"])
    padding = int(config["padding"])

    if len(input_values) != product(config["input_shape"]):
        raise ValueError("input value count does not match input_shape")
    if len(weight_values) != product(config["kernel_shape"]):
        raise ValueError("weight value count does not match kernel_shape")
    if len(bias_values) != output_channels:
        raise ValueError("bias value count must match output channels")
    if input_channels != weight_channels:
        raise ValueError("input and weight channel counts differ")

    acc_values: list[int] = []
    acc_min, acc_max = dtype_range(config["acc_dtype"])

    for oc in range(output_channels):
        for oh in range(output_h):
            for ow in range(output_w):
                acc = int(bias_values[oc])
                for ic in range(input_channels):
                    for kh in range(kernel_h):
                        ih = oh * stride + kh - padding
                        if ih < 0 or ih >= input_h:
                            continue
                        for kw in range(kernel_w):
                            iw = ow * stride + kw - padding
                            if iw < 0 or iw >= input_w:
                                continue
                            acc += (
                                input_values[input_index(ic, ih, iw, input_h, input_w)]
                                * weight_values[
                                    weight_index(
                                        oc,
                                        ic,
                                        kh,
                                        kw,
                                        input_channels,
                                        kernel_h,
                                        kernel_w,
                                    )
                                ]
                            )
                if acc < acc_min or acc > acc_max:
                    raise OverflowError(f"accumulator overflow at oc={oc}, oh={oh}, ow={ow}")
                acc_values.append(acc)

    return acc_values


def load_fixture_values(fixture_dir: Path) -> tuple[dict, list[int], list[int], list[int]]:
    config = load_config(fixture_dir)
    validate_config(config)
    input_values = read_values(
        fixture_dir / "input_int8.hex",
        config["input_dtype"],
        product(config["input_shape"]),
    )
    weight_values = read_values(
        fixture_dir / "weight_int8.hex",
        config["weight_dtype"],
        product(config["kernel_shape"]),
    )
    bias_values = read_values(
        fixture_dir / "bias_int32.hex",
        config["bias_dtype"],
        int(config["output_shape"][0]),
    )
    return config, input_values, weight_values, bias_values


def run_reference(fixture_dir: Path, check_only: bool = False) -> Path:
    config, input_values, weight_values, bias_values = load_fixture_values(fixture_dir)
    acc_values = compute_accumulator(config, input_values, weight_values, bias_values)
    expected_path = fixture_dir / "expected_acc_int32.hex"

    if check_only:
        expected_values = read_values(
            expected_path, config["acc_dtype"], product(config["output_shape"])
        )
        if expected_values != acc_values:
            raise ValueError("existing expected_acc_int32.hex does not match reference")
    else:
        write_values(expected_path, acc_values)

    return expected_path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture", required=True, help="Path to a fixture directory")
    parser.add_argument(
        "--check-only",
        action="store_true",
        help="Validate existing expected_acc_int32.hex without rewriting it",
    )
    args = parser.parse_args()

    fixture_dir = Path(args.fixture)
    expected_path = run_reference(fixture_dir, check_only=args.check_only)
    config = load_config(fixture_dir)
    output_shape = validate_config(config)
    expected_count = product(output_shape)

    action = "checked" if args.check_only else "wrote"
    print(f"fixture: {config['fixture_id']}")
    print(f"output_shape: {output_shape}")
    print(f"{action}: {expected_path}")
    print(f"values: {expected_count}")
    print(f"sha256: {sha256_file(expected_path)}")
    print("PASS: output_shape matches layer_config.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
