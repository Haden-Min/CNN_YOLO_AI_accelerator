#!/usr/bin/env python3
"""Extract TFLite metadata and FPGA activation/requant parameters.

RTL contract:
  real_scale ~= multiplier / 2**shift
  y = sat_int8(round_nearest_away(acc * multiplier / 2**shift) + zero_point)
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")

import numpy as np
import tensorflow as tf

MODE_LINEAR = 0
MODE_LEAKY_RELU = 1
INT32_MIN = -(1 << 31)
INT32_MAX = (1 << 31) - 1
MAX_SHIFT = 63


def arguments() -> argparse.Namespace:
    here = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--model",
        type=Path,
        default=here / "yolov3-tiny-416_full_integer_quant.tflite",
    )
    parser.add_argument(
        "--output-dir", type=Path, default=here / "requant_output"
    )
    parser.add_argument("--leaky-alpha", type=float, default=0.1)
    return parser.parse_args()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def qdict(tensor: dict[str, Any]) -> dict[str, Any]:
    q = tensor["quantization_parameters"]
    return {
        "scales": [float(x) for x in q["scales"]],
        "zero_points": [int(x) for x in q["zero_points"]],
        "quantized_dimension": int(q["quantized_dimension"]),
    }


def tdict(tensor: dict[str, Any]) -> dict[str, Any]:
    return {
        "index": int(tensor["index"]),
        "name": tensor["name"],
        "shape": [int(x) for x in tensor["shape"]],
        "dtype": np.dtype(tensor["dtype"]).name,
        "quantization": qdict(tensor),
    }


def scalar(values: list[Any], name: str) -> Any:
    if len(values) != 1:
        raise ValueError(f"{name}: expected one value, got {len(values)}")
    return values[0]


def per_channel(values: list[Any], count: int, name: str) -> list[Any]:
    if len(values) == 1:
        return values * count
    if len(values) == count:
        return values
    raise ValueError(f"{name}: got {len(values)}, expected 1 or {count}")


def encode_scale(real_scale: float) -> dict[str, Any]:
    """Min-error signed-INT32 multiplier and 0..63 right shift."""
    if not math.isfinite(real_scale) or real_scale < 0:
        raise ValueError(f"invalid scale {real_scale}")
    if real_scale == 0:
        return {
            "real_scale": 0.0,
            "multiplier": 0,
            "shift": 0,
            "approximated_scale": 0.0,
            "absolute_error": 0.0,
            "relative_error": 0.0,
        }

    candidates = []
    for shift in range(MAX_SHIFT + 1):
        multiplier = int(math.floor(math.ldexp(real_scale, shift) + 0.5))
        if 0 <= multiplier <= INT32_MAX:
            approximation = math.ldexp(float(multiplier), -shift)
            error = abs(approximation - real_scale)
            # Equal error: prefer the larger shift for finer nominal resolution.
            candidates.append((error, -shift, multiplier, approximation))
    if not candidates:
        raise ValueError(f"scale {real_scale} is not representable by this RTL")

    error, minus_shift, multiplier, approximation = min(candidates)
    return {
        "real_scale": real_scale,
        "multiplier": multiplier,
        "shift": -minus_shift,
        "approximated_scale": approximation,
        "absolute_error": error,
        "relative_error": error / real_scale,
    }


def consumers_of(operators):
    result = {}

    for op_index, op in enumerate(operators):
        # Interpreter가 추가한 실행 최적화 pseudo-op는
        # 원래 TFLite 그래프 연결을 분석할 때 제외한다.
        if op["op_name"] == "DELEGATE":
            continue

        for tensor_index in op["inputs"]:
            tensor_index = int(tensor_index)

            if tensor_index >= 0:
                result.setdefault(tensor_index, []).append(op_index)

    return result


def constant(
    interpreter: tf.lite.Interpreter, tensor: dict[str, Any], name: str
) -> np.ndarray:
    try:
        return interpreter.get_tensor(int(tensor["index"]))
    except ValueError as error:
        raise ValueError(f"cannot read constant {name}: {tensor['name']}") from error


def extract_layer(
    ordinal: int,
    op_index: int,
    op: dict[str, Any],
    operators: list[dict[str, Any]],
    consumers: dict[int, list[int]],
    tensors: dict[int, dict[str, Any]],
    interpreter: tf.lite.Interpreter,
    alpha: float,
) -> dict[str, Any]:
    inputs = [int(x) for x in op["inputs"] if int(x) >= 0]
    outputs = [int(x) for x in op["outputs"] if int(x) >= 0]
    if len(inputs) < 2 or len(outputs) != 1:
        raise ValueError(f"unexpected CONV_2D signature at op {op_index}")

    tin = tensors[inputs[0]]
    tw = tensors[inputs[1]]
    tb = tensors[inputs[2]] if len(inputs) > 2 else None
    tconv = tensors[outputs[0]]
    teffective = tconv
    mode, activation, activation_op = MODE_LINEAR, "LINEAR", None
    warnings: list[str] = []

    following = consumers.get(outputs[0], [])
    if len(following) == 1 and operators[following[0]]["op_name"] == "LEAKY_RELU":
        activation_op = following[0]
        leaky_outputs = [
            int(x) for x in operators[activation_op]["outputs"] if int(x) >= 0
        ]
        if len(leaky_outputs) != 1:
            raise ValueError(f"unexpected LEAKY_RELU signature at op {activation_op}")
        teffective = tensors[leaky_outputs[0]]
        mode, activation = MODE_LEAKY_RELU, "LEAKY_RELU"
        warnings.append(
            "TFLite has separate CONV_2D and LEAKY_RELU quantization boundaries; "
            "direct fusion removes the intermediate INT8 rounding and may not be "
            "bit-exact with TFLite."
        )

    tinj, twj, tconvj, teffj = map(tdict, (tin, tw, tconv, teffective))
    tbj = tdict(tb) if tb is not None else None
    for role, item in (("input", tinj), ("weight", twj), ("output", teffj)):
        if item["dtype"] != "int8":
            warnings.append(f"{role} dtype is {item['dtype']}, RTL expects int8")

    sx = float(scalar(tinj["quantization"]["scales"], "input scale"))
    zx = int(scalar(tinj["quantization"]["zero_points"], "input zero-point"))
    sconv = float(scalar(tconvj["quantization"]["scales"], "Conv output scale"))
    zconv = int(
        scalar(tconvj["quantization"]["zero_points"], "Conv output zero-point")
    )
    sy = float(scalar(teffj["quantization"]["scales"], "effective output scale"))
    zy = int(
        scalar(teffj["quantization"]["zero_points"], "effective output zero-point")
    )

    wshape = twj["shape"]
    wdim = twj["quantization"]["quantized_dimension"]
    if not 0 <= wdim < len(wshape):
        raise ValueError(f"invalid weight quantized_dimension {wdim}")
    channel_count = wshape[wdim]
    sw = [
        float(x)
        for x in per_channel(
            twj["quantization"]["scales"], channel_count, "weight scales"
        )
    ]
    zw = [
        int(x)
        for x in per_channel(
            twj["quantization"]["zero_points"], channel_count, "weight zero-points"
        )
    ]

    weights = constant(interpreter, tw, f"Conv {ordinal} weights").astype(np.int64)
    sum_axes = tuple(i for i in range(weights.ndim) if i != wdim)
    weight_sums = np.sum(weights, axis=sum_axes, dtype=np.int64).reshape(-1)

    if tb is not None:
        bias = constant(interpreter, tb, f"Conv {ordinal} bias").astype(np.int64).reshape(-1)
        sb = [
            float(x)
            for x in per_channel(
                tbj["quantization"]["scales"], channel_count, "bias scales"
            )
        ]
        zb = [
            int(x)
            for x in per_channel(
                tbj["quantization"]["zero_points"], channel_count, "bias zero-points"
            )
        ]
    else:
        bias = np.zeros(channel_count, dtype=np.int64)
        sb = [sx * scale for scale in sw]
        zb = [0] * channel_count

    if len(weight_sums) != channel_count or len(bias) != channel_count:
        raise ValueError(f"channel count mismatch in Conv {ordinal}")
    if any(value != 0 for value in zw):
        warnings.append(
            "nonzero weight zero-point cannot be fully corrected by static bias"
        )

    channels = []
    for oc in range(channel_count):
        correction = -zx * int(weight_sums[oc])
        effective_bias = int(bias[oc]) + correction
        positive = encode_scale(sx * sw[oc] / sy)
        negative = encode_scale(
            positive["real_scale"] * alpha if mode == MODE_LEAKY_RELU
            else positive["real_scale"]
        )
        conv_only = encode_scale(sx * sw[oc] / sconv)
        channels.append(
            {
                "output_channel": oc,
                "input_scale": sx,
                "input_zero_point": zx,
                "weight_scale": sw[oc],
                "weight_zero_point": zw[oc],
                "weight_sum_int": int(weight_sums[oc]),
                "bias_int32": int(bias[oc]),
                "bias_scale": sb[oc],
                "bias_zero_point": zb[oc],
                "expected_bias_scale": sx * sw[oc],
                "bias_scale_matches": math.isclose(
                    sb[oc], sx * sw[oc], rel_tol=2e-6, abs_tol=1e-12
                ),
                "raw_mac_accumulator_correction": correction,
                "effective_bias_for_raw_qx_times_qw": effective_bias,
                "effective_bias_fits_int32": INT32_MIN <= effective_bias <= INT32_MAX,
                "conv_only_requant": {
                    "output_scale": sconv,
                    "zero_point": zconv,
                    **conv_only,
                },
                "fused_requant": {
                    "output_scale": sy,
                    "zero_point": zy,
                    "positive": positive,
                    "negative": negative,
                },
                "rtl_register_values": {
                    "activation_mode": mode,
                    "multiplier_pos": positive["multiplier"],
                    "shift_pos": positive["shift"],
                    "multiplier_neg": negative["multiplier"],
                    "shift_neg": negative["shift"],
                    "zero_point": zy,
                },
            }
        )

    if any(not x["bias_scale_matches"] for x in channels):
        warnings.append("bias_scale != input_scale * weight_scale on some channels")
    if any(not x["effective_bias_fits_int32"] for x in channels):
        warnings.append("corrected bias exceeds INT32 on some channels")

    return {
        "conv_ordinal": ordinal,
        "conv_operator_index": op_index,
        "activation": {
            "name": activation,
            "mode": mode,
            "operator_index": activation_op,
            "leaky_alpha": alpha if mode == MODE_LEAKY_RELU else None,
        },
        "output_channels": channel_count,
        "tensors": {
            "input": tinj,
            "weight": twj,
            "bias": tbj,
            "conv_output": tconvj,
            "effective_fused_output": teffj,
        },
        "channels": channels,
        "warnings": warnings,
    }


CSV_FIELDS = [
    "conv_ordinal", "conv_operator_index", "activation_name", "activation_mode",
    "output_channel", "input_scale", "input_zero_point", "weight_scale",
    "weight_zero_point", "weight_sum_int", "bias_int32", "bias_scale",
    "expected_bias_scale", "bias_scale_matches", "raw_mac_accumulator_correction",
    "effective_bias_for_raw_qx_times_qw", "effective_bias_fits_int32",
    "output_scale", "multiplier_pos", "shift_pos", "positive_relative_error",
    "multiplier_neg", "shift_neg", "negative_relative_error", "zero_point",
]


def write_csv(path: Path, layers: list[dict[str, Any]]) -> None:
    with path.open("w", newline="", encoding="utf-8-sig") as file:
        writer = csv.DictWriter(file, fieldnames=CSV_FIELDS)
        writer.writeheader()
        for layer in layers:
            for c in layer["channels"]:
                fused = c["fused_requant"]
                reg = c["rtl_register_values"]
                writer.writerow({
                    "conv_ordinal": layer["conv_ordinal"],
                    "conv_operator_index": layer["conv_operator_index"],
                    "activation_name": layer["activation"]["name"],
                    "activation_mode": layer["activation"]["mode"],
                    "output_channel": c["output_channel"],
                    "input_scale": c["input_scale"],
                    "input_zero_point": c["input_zero_point"],
                    "weight_scale": c["weight_scale"],
                    "weight_zero_point": c["weight_zero_point"],
                    "weight_sum_int": c["weight_sum_int"],
                    "bias_int32": c["bias_int32"],
                    "bias_scale": c["bias_scale"],
                    "expected_bias_scale": c["expected_bias_scale"],
                    "bias_scale_matches": c["bias_scale_matches"],
                    "raw_mac_accumulator_correction": c["raw_mac_accumulator_correction"],
                    "effective_bias_for_raw_qx_times_qw": c["effective_bias_for_raw_qx_times_qw"],
                    "effective_bias_fits_int32": c["effective_bias_fits_int32"],
                    "output_scale": fused["output_scale"],
                    "multiplier_pos": reg["multiplier_pos"],
                    "shift_pos": reg["shift_pos"],
                    "positive_relative_error": fused["positive"]["relative_error"],
                    "multiplier_neg": reg["multiplier_neg"],
                    "shift_neg": reg["shift_neg"],
                    "negative_relative_error": fused["negative"]["relative_error"],
                    "zero_point": reg["zero_point"],
                })


def write_summary(path: Path, model: Path, layers: list[dict[str, Any]]) -> None:
    lines = [
        "YOLOv3-Tiny requant parameter summary",
        f"Model: {model}",
        f"CONV_2D layers: {len(layers)}",
        "Formula: real_scale ~= multiplier / 2^shift",
        "Rounding: nearest, exact halves away from zero",
        "",
    ]
    for layer in layers:
        c0 = layer["channels"][0]
        scales = [c["weight_scale"] for c in layer["channels"]]
        lines += [
            f"Conv {layer['conv_ordinal']} (op {layer['conv_operator_index']}):",
            f"  activation={layer['activation']['name']} mode={layer['activation']['mode']}",
            f"  output_channels={layer['output_channels']}",
            f"  input scale/zp={c0['input_scale']:.10g}/{c0['input_zero_point']}",
            f"  weight scales={len(scales)} range=[{min(scales):.10g}, {max(scales):.10g}]",
            f"  output scale/zp={c0['fused_requant']['output_scale']:.10g}/{c0['rtl_register_values']['zero_point']}",
            f"  channel0 registers={c0['rtl_register_values']}",
        ]
        lines += [f"  WARNING: {warning}" for warning in layer["warnings"]]
        lines.append("")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    args = arguments()
    model = args.model.resolve()
    out = args.output_dir.resolve()
    if not model.is_file():
        raise FileNotFoundError(model)
    if not 0 <= args.leaky_alpha <= 1:
        raise ValueError("--leaky-alpha must be in [0, 1]")
    out.mkdir(parents=True, exist_ok=True)

    interpreter = tf.lite.Interpreter(
        model_path=str(model),
        experimental_preserve_all_tensors=True,
        experimental_op_resolver_type=(
            tf.lite.experimental.OpResolverType.BUILTIN_WITHOUT_DEFAULT_DELEGATES
             ),
    )
    interpreter.allocate_tensors()
    tensors = {int(t["index"]): t for t in interpreter.get_tensor_details()}
    operators = interpreter._get_ops_details()
    consumers = consumers_of(operators)

    layers = []
    for op_index, op in enumerate(operators):
        if op["op_name"] == "CONV_2D":
            layers.append(extract_layer(
                len(layers), op_index, op, operators, consumers, tensors,
                interpreter, args.leaky_alpha
            ))
    if not layers:
        raise RuntimeError("no CONV_2D operators found")

    histogram: dict[str, int] = {}
    for op in operators:
        histogram[op["op_name"]] = histogram.get(op["op_name"], 0) + 1

    master = {
        "schema_version": 1,
        "generated_utc": datetime.now(timezone.utc).isoformat(),
        "model": {
            "path": str(model),
            "size_bytes": model.stat().st_size,
            "sha256": sha256(model),
            "inputs": [tdict(t) for t in interpreter.get_input_details()],
            "outputs": [tdict(t) for t in interpreter.get_output_details()],
            "operator_histogram": histogram,
        },
        "rtl_contract": {
            "real_scale_equation": "real_scale ~= multiplier / 2**shift",
            "rounding": "nearest_with_exact_halves_away_from_zero",
            "shift_range": [0, MAX_SHIFT],
            "output_range": [-128, 127],
            "activation_modes": {"0": "LINEAR", "1": "LEAKY_RELU"},
        },
        "notes": [
            "rtl_register_values is the six-port parameter set for each output channel.",
            "Use effective_bias_for_raw_qx_times_qw when hardware accumulates raw qx*qw.",
            "conv_only_requant preserves the TFLite Conv quantization boundary.",
            "fused_requant maps the corrected Conv accumulator directly through a following LeakyReLU.",
        ],
        "layers": layers,
        "warnings": sorted({w for layer in layers for w in layer["warnings"]}),
    }

    json_path = out / "yolov3_tiny_requant_params.json"
    csv_path = out / "yolov3_tiny_requant_params.csv"
    summary_path = out / "yolov3_tiny_requant_summary.txt"
    json_path.write_text(json.dumps(master, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    write_csv(csv_path, layers)
    write_summary(summary_path, model, layers)

    print(f"PASS: extracted {len(layers)} CONV_2D layers")
    print(f"JSON   : {json_path}")
    print(f"CSV    : {csv_path}")
    print(f"SUMMARY: {summary_path}")
    print(f"Warnings: {len(master['warnings'])} unique")


if __name__ == "__main__":
    main()
