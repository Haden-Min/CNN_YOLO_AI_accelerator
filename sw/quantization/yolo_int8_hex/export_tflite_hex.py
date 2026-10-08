"""Export TFLite CONV_2D constants for the project's PYNQ tile accelerator.

Requires: pip install numpy tflite flatbuffers
Usage: python export_tflite_hex.py --model MODEL.tflite --output-dir hex
"""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
import tflite


def quant(t):
    q = t.Quantization()
    return {
        "scales": [float(q.Scale(i)) for i in range(q.ScaleLength())],
        "zero_points": [int(q.ZeroPoint(i)) for i in range(q.ZeroPointLength())],
        "quantized_dimension": int(q.QuantizedDimension()),
    } if q else {}


def info(t):
    return {"name": t.Name().decode(), "shape": t.ShapeAsNumpy().tolist(),
            "type": int(t.Type()), "quantization": quant(t)}


def constant(model, tensor, dtype):
    data = model.Buffers(tensor.Buffer()).DataAsNumpy()
    if not isinstance(data, np.ndarray):
        raise ValueError("Missing inline constant buffer")
    return np.frombuffer(data.tobytes(), dtype=dtype).reshape(tensor.ShapeAsNumpy())


def write_hex(path, values, bits):
    flat = np.asarray(values).reshape(-1).astype(np.int64)
    encoded = flat & ((1 << bits) - 1)
    with path.open("w", encoding="ascii", newline="\n") as f:
        for start in range(0, flat.size, 65536):
            f.writelines(f"{int(x):0{bits // 4}X}\n" for x in encoded[start:start+65536])
    # Read every exported word back, checking order and two's-complement encoding.
    with path.open(encoding="ascii") as f:
        decoded = np.fromiter((int(line, 16) for line in f), dtype=np.uint64)
    np.testing.assert_array_equal(decoded, encoded.astype(np.uint64))
    return {"file": path.name, "words": int(flat.size), "word_bits": bits,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


def export(model_path, out):
    data = model_path.read_bytes()
    if data[4:8] != b"TFL3":
        raise ValueError("Not a TFLite model")
    model = tflite.Model.GetRootAsModel(data, 0)
    if model.SubgraphsLength() != 1:
        raise ValueError("This exporter requires a single subgraph")
    graph = model.Subgraphs(0)
    out.mkdir(parents=True, exist_ok=True)
    layers = []
    for op_index in range(graph.OperatorsLength()):
        op = graph.Operators(op_index)
        code = model.OperatorCodes(op.OpcodeIndex())
        if max(code.BuiltinCode(), code.DeprecatedBuiltinCode()) != tflite.BuiltinOperator.CONV_2D:
            continue
        x, w, y = (graph.Tensors(int(i)) for i in
                   (op.Inputs(0), op.Inputs(1), op.Outputs(0)))
        if w.Type() != tflite.TensorType.INT8 or x.Type() != tflite.TensorType.INT8:
            raise ValueError("Expected INT8 input and weights")
        weights = constant(model, w, np.int8)
        if weights.ndim != 4:
            raise ValueError("Expected OHWI weights")
        oc, kh, kw, ic = weights.shape
        qw, qx = quant(w), quant(x)
        if any(qw["zero_points"]) or len(qx["zero_points"]) != 1:
            raise ValueError("Requires symmetric weights and per-tensor input quantization")
        if len(qw["scales"]) not in (1, oc) or (len(qw["scales"]) > 1 and qw["quantized_dimension"] != 0):
            raise ValueError("Unexpected weight quantization axis")
        if op.InputsLength() > 2 and op.Inputs(2) >= 0:
            bt = graph.Tensors(op.Inputs(2))
            if bt.Type() != tflite.TensorType.INT32:
                raise ValueError("Expected INT32 bias")
            bias = constant(model, bt, "<i4").astype(np.int64)
            qb = quant(bt)
            if any(qb["zero_points"]) or not np.allclose(qb["scales"], np.array(qw["scales"]) * qx["scales"][0], rtol=2e-6, atol=1e-12):
                raise ValueError("Bias quantization incompatible with raw MAC")
        else:
            bt = None
            bias = np.zeros(oc, dtype=np.int64)
        if bias.shape != (oc,):
            raise ValueError("Unexpected bias shape")
        ordered = weights.transpose(0, 3, 1, 2).copy()
        np.testing.assert_array_equal(ordered.transpose(0, 2, 3, 1), weights)
        corrected = bias - qx["zero_points"][0] * ordered.astype(np.int64).sum(axis=(1, 2, 3))
        if np.any(corrected < -(1 << 31)) or np.any(corrected >= (1 << 31)):
            raise ValueError("Corrected bias does not fit INT32")
        folder = out / f"conv_{len(layers):02d}"
        folder.mkdir(exist_ok=True)
        files = {
            "weights": write_hex(folder / "weights_oihw_int8.hex", ordered, 8),
            "bias": write_hex(folder / "bias_int32.hex", bias, 32),
            "bias_raw_mac": write_hex(folder / "bias_raw_mac_int32.hex", corrected, 32),
        }
        if (kh, kw) == (3, 3):
            packets = np.empty((oc, ic, 10), dtype=np.uint32)
            packets[:, :, :9] = ordered.reshape(oc, ic, 9).view(np.uint8)
            packets[:, :, 9] = (corrected & 0xFFFFFFFF).astype(np.uint32)[:, None]
            files["dma_parameters"] = write_hex(folder / "params_dma32.hex", packets, 32)
        options = tflite.Conv2DOptions()
        tab = op.BuiltinOptions()
        options.Init(tab.Bytes, tab.Pos)
        layer = {"conv_ordinal": len(layers), "operator_index": op_index,
                 "directory": folder.name, "shape_oihw": list(ordered.shape),
                 "input": info(x), "weight": info(w), "conv_output": info(y),
                 "bias": info(bt) if bt else None,
                 "padding_enum": options.Padding(),
                 "stride_hw": [options.StrideH(), options.StrideW()],
                 "fused_activation_enum": options.FusedActivationFunction(),
                 "files": files}
        layers.append(layer)
        print(f"{folder.name}: OIHW={list(ordered.shape)}, weights={ordered.size:,}, HEX round-trip PASS")
    if not layers:
        raise ValueError("No Conv layers found")
    manifest = {"model": str(model_path.resolve()), "model_sha256": hashlib.sha256(data).hexdigest(),
                "layout": "OIHW: output channel, input channel, kernel row, kernel column (column fastest)",
                "encoding": "ASCII hexadecimal, one word per line, two's complement, no address records",
                "dma_layout": "[OC][IC][10]: 9 weights in low byte of uint32, then corrected INT32 bias",
                "total_weight_count": sum(v["files"]["weights"]["words"] for v in layers),
                "layers": layers}
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"PASS: {len(layers)} layers, {manifest['total_weight_count']:,} INT8 weights")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, default=Path("hex"))
    args = parser.parse_args()
    export(args.model, args.output_dir)
