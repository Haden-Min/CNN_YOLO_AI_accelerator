#!/usr/bin/env python3
"""Convert signed fixture files into RTL-friendly two's-complement memories."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from sw.golden.model.conv2d_int8_reference import (  # noqa: E402
    load_config,
    product,
    read_values,
    validate_config,
)


MEMORY_SPECS = [
    ("input_int8.hex", "input_int8.mem", "input_dtype", "input_shape", 8),
    ("weight_int8.hex", "weight_int8.mem", "weight_dtype", "kernel_shape", 8),
    ("bias_int32.hex", "bias_int32.mem", "bias_dtype", "bias_count", 32),
    (
        "expected_acc_int32.hex",
        "expected_acc_int32.mem",
        "acc_dtype",
        "output_shape",
        32,
    ),
]


def rel_for_verilog(path: Path) -> str:
    return path.relative_to(REPO_ROOT).as_posix()


def encode_twos_complement(value: int, bits: int) -> str:
    lo = -(2 ** (bits - 1))
    hi = 2 ** (bits - 1) - 1
    if value < lo or value > hi:
        raise ValueError(f"{value} outside signed {bits}-bit range [{lo}, {hi}]")
    encoded = value & ((1 << bits) - 1)
    width = bits // 4
    return f"{encoded:0{width}x}"


def count_for_shape(config: dict, shape_key: str) -> int:
    if shape_key == "bias_count":
        return int(config["output_shape"][0])
    return product(config[shape_key])


def write_mem_file(source: Path, target: Path, dtype: str, count: int, bits: int) -> None:
    values = read_values(source, dtype, count)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(
        "".join(f"{encode_twos_complement(value, bits)}\n" for value in values),
        encoding="ascii",
    )


def write_fixture_params(config: dict, generated_dir: Path) -> Path:
    fixture_id = config["fixture_id"]
    ic, input_h, input_w = [int(x) for x in config["input_shape"]]
    oc, _, kernel_h, kernel_w = [int(x) for x in config["kernel_shape"]]
    _, output_h, output_w = [int(x) for x in config["output_shape"]]
    stride = int(config["stride"])
    padding = int(config["padding"])

    vh_path = REPO_ROOT / "rtl" / "tb" / "fixture_params.vh"
    vh_path.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "`ifndef FIXTURE_PARAMS_VH",
        "`define FIXTURE_PARAMS_VH",
        "",
        f'`define FIXTURE_ID "{fixture_id}"',
        f"`define FIXTURE_IC {ic}",
        f"`define FIXTURE_OC {oc}",
        f"`define FIXTURE_INPUT_H {input_h}",
        f"`define FIXTURE_INPUT_W {input_w}",
        f"`define FIXTURE_KERNEL_H {kernel_h}",
        f"`define FIXTURE_KERNEL_W {kernel_w}",
        f"`define FIXTURE_OUTPUT_H {output_h}",
        f"`define FIXTURE_OUTPUT_W {output_w}",
        f"`define FIXTURE_STRIDE {stride}",
        f"`define FIXTURE_PADDING {padding}",
        f"`define FIXTURE_INPUT_SIZE {ic * input_h * input_w}",
        f"`define FIXTURE_WEIGHT_SIZE {oc * ic * kernel_h * kernel_w}",
        f"`define FIXTURE_BIAS_SIZE {oc}",
        f"`define FIXTURE_OUTPUT_SIZE {oc * output_h * output_w}",
        "",
        f'`define FIXTURE_INPUT_MEM "{rel_for_verilog(generated_dir / "input_int8.mem")}"',
        f'`define FIXTURE_WEIGHT_MEM "{rel_for_verilog(generated_dir / "weight_int8.mem")}"',
        f'`define FIXTURE_BIAS_MEM "{rel_for_verilog(generated_dir / "bias_int32.mem")}"',
        f'`define FIXTURE_EXPECTED_ACC_MEM "{rel_for_verilog(generated_dir / "expected_acc_int32.mem")}"',
        "",
        "`endif",
        "",
    ]
    vh_path.write_text("\n".join(lines), encoding="ascii")
    return vh_path


def generate_rtl_mem(fixture_dir: Path, output_root: Path) -> tuple[Path, Path]:
    config = load_config(fixture_dir)
    validate_config(config)
    generated_dir = output_root / config["fixture_id"]
    generated_dir.mkdir(parents=True, exist_ok=True)

    for source_name, target_name, dtype_key, shape_key, bits in MEMORY_SPECS:
        write_mem_file(
            fixture_dir / source_name,
            generated_dir / target_name,
            config[dtype_key],
            count_for_shape(config, shape_key),
            bits,
        )

    vh_path = write_fixture_params(config, generated_dir)
    return generated_dir, vh_path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture", required=True, help="Path to a fixture directory")
    parser.add_argument(
        "--output-root",
        default=str(REPO_ROOT / "sw" / "fixture" / "generated"),
        help="Directory for generated RTL memory files",
    )
    args = parser.parse_args()

    generated_dir, vh_path = generate_rtl_mem(Path(args.fixture), Path(args.output_root))
    print(f"generated_mem_dir: {generated_dir}")
    print(f"fixture_params: {vh_path}")
    print("PASS: RTL memory files generated")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
