#!/usr/bin/env python3
"""Hardware-friendly INT8 conv2d reference.

This file is intentionally written close to an RTL implementation style:

- flat input, weight, bias, and output memories
- scalar shape parameters
- explicit nested counters
- fixed output memory allocation before computation
- direct address calculations for CHW / OIHW layout

The JSON file is only used by the command-line wrapper to load scalar
parameters. The convolution datapath itself does not parse JSON, infer shapes,
or grow output lists dynamically.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[3]


def signed_range(bits: int) -> tuple[int, int]:
    return -(1 << (bits - 1)), (1 << (bits - 1)) - 1


def input_addr(ic: int, ih: int, iw: int, INPUT_H: int, INPUT_W: int) -> int:
    return ic * INPUT_H * INPUT_W + ih * INPUT_W + iw


def weight_addr(
    oc: int,
    ic: int,
    kh: int,
    kw: int,
    IC: int,
    KERNEL_H: int,
    KERNEL_W: int,
) -> int:
    return oc * IC * KERNEL_H * KERNEL_W + ic * KERNEL_H * KERNEL_W + kh * KERNEL_W + kw


def output_addr(oc: int, oh: int, ow: int, OUTPUT_H: int, OUTPUT_W: int) -> int:
    return oc * OUTPUT_H * OUTPUT_W + oh * OUTPUT_W + ow


def read_signed_memory(path: Path, expected_count: int, bits: int) -> list[int]:
    lo, hi = signed_range(bits)
    memory = [0] * expected_count
    write_ptr = 0

    with path.open("r", encoding="ascii") as f:
        for line_no, raw_line in enumerate(f, start=1):
            line = raw_line.split("#", 1)[0].strip()
            if not line:
                continue

            tokens = line.replace(",", " ").split()
            for token in tokens:
                if write_ptr >= expected_count:
                    raise ValueError(f"{path}: too many values")

                value = int(token, 0)
                if value < lo or value > hi:
                    raise ValueError(
                        f"{path}:{line_no}: {value} outside signed {bits}-bit range"
                    )

                memory[write_ptr] = value
                write_ptr += 1

    if write_ptr != expected_count:
        raise ValueError(f"{path}: expected {expected_count} values, found {write_ptr}")

    return memory


def write_signed_memory(path: Path, memory: list[int], count: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [""] * count
    for addr in range(count):
        lines[addr] = f"{int(memory[addr])}\n"
    path.write_text("".join(lines), encoding="ascii")


def load_scalar_params(fixture_dir: Path) -> dict[str, int]:
    config_path = fixture_dir / "layer_config.json"
    with config_path.open("r", encoding="ascii") as f:
        config = json.load(f)

    if config["layout"] != "CHW":
        raise ValueError("hw-friendly reference currently supports CHW layout only")

    input_shape = config["input_shape"]
    kernel_shape = config["kernel_shape"]
    output_shape = config["output_shape"]

    return {
        "IC": int(input_shape[0]),
        "INPUT_H": int(input_shape[1]),
        "INPUT_W": int(input_shape[2]),
        "OC": int(kernel_shape[0]),
        "KERNEL_H": int(kernel_shape[2]),
        "KERNEL_W": int(kernel_shape[3]),
        "OUTPUT_H": int(output_shape[1]),
        "OUTPUT_W": int(output_shape[2]),
        "STRIDE": int(config["stride"]),
        "PADDING": int(config["padding"]),
    }


def hw_conv2d_int8_acc(
    input_mem: list[int],
    weight_mem: list[int],
    bias_mem: list[int],
    IC: int,
    INPUT_H: int,
    INPUT_W: int,
    OC: int,
    KERNEL_H: int,
    KERNEL_W: int,
    OUTPUT_H: int,
    OUTPUT_W: int,
    STRIDE: int,
    PADDING: int,
) -> list[int]:
    output_size = OC * OUTPUT_H * OUTPUT_W
    output_mem = [0] * output_size #if output_size=5 -> output_mem = [0,0,0,0,0]
    acc_min, acc_max = signed_range(32)

    for oc in range(OC): #관점 : 출력 매트리스의 n,m번쨰를 채우고 싶은데 그러려면 어떤 데이터의 몇 번째 데이터가 필요한가
        for oh in range(OUTPUT_H):
            for ow in range(OUTPUT_W):
                acc = int(bias_mem[oc]) #누산기를 bias값으로 초기화

                for ic in range(IC): #소문자는 주소를 의미. 한 바퀴에 outchannel의 원소 한 칸씩 만들어짐.
                    for kh in range(KERNEL_H): #커널의 col을 따라 계산
                        ih = oh * STRIDE + kh - PADDING #입력의 몇 번쨰 height를 읽어야 하는가? stride만큼의 보폭만큼 곱해줘야하고, 패딩해준만큼 빼주어야 입력의 주소가 나온다.

                        for kw in range(KERNEL_W):#커널의 row를 따라서 계산
                            iw = ow * STRIDE + kw - PADDING

                            if ih < 0 or ih >= INPUT_H or iw < 0 or iw >= INPUT_W:
                                product = 0
                            else:
                                in_addr = input_addr(ic, ih, iw, INPUT_H, INPUT_W)
                                wt_addr = weight_addr(
                                    oc,
                                    ic,
                                    kh,
                                    kw,
                                    IC,
                                    KERNEL_H,
                                    KERNEL_W,
                                )
                                input_data = int(input_mem[in_addr])
                                weight_data = int(weight_mem[wt_addr])
                                product = input_data * weight_data

                            acc = acc + product

                if acc < acc_min or acc > acc_max:
                    raise OverflowError("INT32 accumulator overflow")

                out_addr = output_addr(oc, oh, ow, OUTPUT_H, OUTPUT_W)
                output_mem[out_addr] = acc

    return output_mem


def compare_memory(expected_mem: list[int], actual_mem: list[int], count: int) -> int:
    mismatch_count = 0
    for addr in range(count):
        if expected_mem[addr] != actual_mem[addr]:
            mismatch_count += 1
            print(
                f"mismatch addr={addr} "
                f"expected={expected_mem[addr]} actual={actual_mem[addr]}"
            )
    return mismatch_count


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as f:
        while True:
            chunk = f.read(65536)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def run_hw_friendly_reference(fixture_dir: Path, write_expected: bool) -> int:
    p = load_scalar_params(fixture_dir)

    input_size = p["IC"] * p["INPUT_H"] * p["INPUT_W"]
    weight_size = p["OC"] * p["IC"] * p["KERNEL_H"] * p["KERNEL_W"]
    bias_size = p["OC"]
    output_size = p["OC"] * p["OUTPUT_H"] * p["OUTPUT_W"]

    input_mem = read_signed_memory(fixture_dir / "input_int8.hex", input_size, 8)
    weight_mem = read_signed_memory(fixture_dir / "weight_int8.hex", weight_size, 8)
    bias_mem = read_signed_memory(fixture_dir / "bias_int32.hex", bias_size, 32)

    actual_mem = hw_conv2d_int8_acc(
        input_mem=input_mem,
        weight_mem=weight_mem,
        bias_mem=bias_mem,
        IC=p["IC"],
        INPUT_H=p["INPUT_H"],
        INPUT_W=p["INPUT_W"],
        OC=p["OC"],
        KERNEL_H=p["KERNEL_H"],
        KERNEL_W=p["KERNEL_W"],
        OUTPUT_H=p["OUTPUT_H"],
        OUTPUT_W=p["OUTPUT_W"],
        STRIDE=p["STRIDE"],
        PADDING=p["PADDING"],
    )

    expected_path = fixture_dir / "expected_acc_int32.hex"
    if write_expected:
        write_signed_memory(expected_path, actual_mem, output_size)
        print(f"wrote: {expected_path}")
    else:
        expected_mem = read_signed_memory(expected_path, output_size, 32)
        mismatch_count = compare_memory(expected_mem, actual_mem, output_size)
        print(f"Compared values: {output_size}")
        print(f"Mismatch count: {mismatch_count}")
        if mismatch_count != 0:
            print("FAIL")
            return 1

    print(
        "params: "
        f"IC={p['IC']} OC={p['OC']} "
        f"INPUT={p['INPUT_H']}x{p['INPUT_W']} "
        f"KERNEL={p['KERNEL_H']}x{p['KERNEL_W']} "
        f"OUTPUT={p['OUTPUT_H']}x{p['OUTPUT_W']} "
        f"STRIDE={p['STRIDE']} PADDING={p['PADDING']}"
    )
    print(f"sha256: {sha256_file(expected_path)}")
    print("PASS")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--fixture",
        default=str(REPO_ROOT / "sw" / "fixture" / "single_conv_001"),
        help="Path to a fixture directory",
    )
    parser.add_argument(
        "--write-expected",
        action="store_true",
        help="Rewrite expected_acc_int32.hex instead of comparing against it",
    )
    args = parser.parse_args()

    return run_hw_friendly_reference(Path(args.fixture), args.write_expected)


if __name__ == "__main__":
    raise SystemExit(main())
