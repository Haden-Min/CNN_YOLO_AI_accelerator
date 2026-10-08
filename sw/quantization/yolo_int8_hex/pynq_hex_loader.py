"""Load actual base-16 HEX exported by export_tflite_hex.py. Requires numpy."""
from pathlib import Path
import json
import numpy as np


def read_hex(path, bits):
    with Path(path).open(encoding="ascii") as f:
        values = [int(line.strip(), 16) for line in f if line.strip()]
    if any(v < 0 or v >= (1 << bits) for v in values):
        raise ValueError("HEX word out of range")
    return np.asarray(values, dtype=np.uint8 if bits == 8 else np.uint32)


def load_layer(root, conv_ordinal):
    root = Path(root)
    manifest = json.loads((root / "manifest.json").read_text(encoding="utf-8"))
    layer = manifest["layers"][conv_ordinal]
    folder = root / layer["directory"]
    weights = read_hex(folder / "weights_oihw_int8.hex", 8).view(np.int8).reshape(layer["shape_oihw"])
    bias = read_hex(folder / "bias_raw_mac_int32.hex", 32).view(np.int32)
    if bias.size != weights.shape[0]:
        raise ValueError("Bias count mismatch")
    return weights, bias, layer


def parameter_packet(weights, bias, output_channel, input_channel):
    """Copy returned uint32[10] into pynq.allocate buffer for current RTL.

    For each OC, reset/start a new accumulation. For each IC, load this packet
    then run its input tile, following smoke_test_single_conv.py sequencing.
    The RTL applies bias once after the final IC; repeat it in every packet.
    """
    if weights.shape[2:] != (3, 3):
        raise ValueError("Current tile RTL supports only 3x3 kernels")
    packet = np.empty(10, dtype=np.uint32)
    packet[:9] = weights[output_channel, input_channel].reshape(-1).view(np.uint8)
    packet[9] = int(bias[output_channel]) & 0xFFFFFFFF
    return packet
