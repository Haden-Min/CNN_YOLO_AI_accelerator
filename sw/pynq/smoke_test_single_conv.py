#!/usr/bin/env python3
"""PYNQ AXI-DMA smoke test for serial-IC, OC=1 tile convolution."""

from __future__ import annotations

import argparse
import json
import time
from pathlib import Path

import numpy as np


REG_CTRL = 0x00
REG_STATUS = 0x04
REG_STREAM_IN = 0x08
REG_STREAM_OUT = 0x0C
REG_EXPECTED_IN = 0x10
REG_EXPECTED_OUT = 0x14
REG_ERROR = 0x18
REG_PARAM_WORDS = 0x1C
REG_TOTAL_IC = 0x20
REG_CURRENT_IC = 0x24

CTRL_RUN_TILE = 1 << 0
CTRL_CLEAR_DONE = 1 << 1
CTRL_SOFT_RESET = 1 << 2
CTRL_LOAD_PARAM = 1 << 3

STATUS_IDLE = 1 << 0
STATUS_DONE = 1 << 4
STATUS_ERROR = 1 << 5
STATUS_PARAM_LOADED = 1 << 11


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bitstream", type=Path, required=True)
    parser.add_argument("--fixture", type=Path, required=True)
    parser.add_argument("--dma-name", default="axi_dma_0")
    parser.add_argument("--accel-name", default="cnn_accel_0")
    return parser.parse_args()


def load_vector(path: Path, dtype: np.dtype) -> np.ndarray:
    values = np.loadtxt(path, dtype=np.int64)
    return np.atleast_1d(values).astype(dtype)


def encode_i8_words(values: np.ndarray) -> np.ndarray:
    """Put one signed INT8 value in the low byte of each uint32 stream word."""
    return (
        np.asarray(values, dtype=np.int8)
        .reshape(-1)
        .view(np.uint8)
        .astype(np.uint32)
    )


def build_payloads(
    fixture: Path,
) -> tuple[list[np.ndarray], list[np.ndarray], np.ndarray]:
    config = json.loads((fixture / "layer_config.json").read_text())
    ic, in_h, in_w = config["input_shape"]
    oc, out_h, out_w = config["output_shape"]
    weight_oc, weight_ic, k_h, k_w = config["kernel_shape"]

    if config["layout"] != "CHW":
        raise ValueError("Only CHW fixtures are supported")
    if (oc, weight_oc) != (1, 1):
        raise ValueError("The current RTL/packet contract is limited to OC=1")
    if ic != weight_ic or not 1 <= ic <= 1024:
        raise ValueError("Input and weight IC must match and be in the range 1..1024")
    if in_h != in_w or in_h not in (16, 28):
        raise ValueError("The supported fixed tile bitstreams are 16x16 and 28x28")
    if (k_h, k_w) != (3, 3):
        raise ValueError("The tile RTL implements one valid 3x3 convolution")
    if (out_h, out_w) != (in_h - 2, in_w - 2):
        raise ValueError("A valid 3x3 tile must produce (H-2)x(W-2) output")

    input_i8 = load_vector(fixture / "input_int8.hex", np.int8)
    weight_i8 = load_vector(fixture / "weight_int8.hex", np.int8)
    bias_i32 = load_vector(fixture / "bias_int32.hex", np.int32)
    expected_i32 = load_vector(fixture / "expected_acc_int32.hex", np.int32)

    if input_i8.size != ic * in_h * in_w:
        raise ValueError("Input fixture length does not match layer_config.json")
    if weight_i8.size != oc * ic * k_h * k_w:
        raise ValueError("Weight fixture length does not match layer_config.json")
    if bias_i32.size != oc:
        raise ValueError("Bias fixture length does not match layer_config.json")
    if expected_i32.size != oc * out_h * out_w:
        raise ValueError("Expected fixture length does not match layer_config.json")

    weights_by_ic = weight_i8.reshape(ic, k_h * k_w)
    inputs_by_ic = input_i8.reshape(ic, in_h * in_w)
    parameter_packets = [
        np.concatenate(
            (encode_i8_words(weights_by_ic[channel]), bias_i32.astype(np.uint32))
        )
        for channel in range(ic)
    ]
    tile_packets = [encode_i8_words(inputs_by_ic[channel]) for channel in range(ic)]
    return parameter_packets, tile_packets, expected_i32


def wait_for_done(accel: object, timeout_seconds: float = 10.0) -> int:
    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        status = int(accel.read(REG_STATUS))
        if status & STATUS_DONE:
            return status
    raise TimeoutError("Timed out waiting for accelerator completion")


def main() -> None:
    args = parse_args()
    parameter_packets, tile_packets, expected_i32 = build_payloads(args.fixture)
    input_channels = len(tile_packets)

    try:
        from pynq import Overlay, allocate
    except ImportError as exc:
        raise RuntimeError("This command must run in a PYNQ Python environment") from exc

    overlay = Overlay(str(args.bitstream))
    dma = getattr(overlay, args.dma_name)
    accel = getattr(overlay, args.accel_name)

    expected_input_words = int(accel.read(REG_EXPECTED_IN))
    expected_output_words = int(accel.read(REG_EXPECTED_OUT))
    expected_parameter_words = int(accel.read(REG_PARAM_WORDS))
    if expected_parameter_words != parameter_packets[0].size:
        raise RuntimeError(
            f"Bitstream expects {expected_parameter_words} parameter words, "
            f"but fixture provides {parameter_packets[0].size} per input channel"
        )
    if any(packet.size != expected_input_words for packet in tile_packets):
        raise RuntimeError(
            f"Bitstream expects {expected_input_words} input words, "
            "but at least one input-channel tile has a different size"
        )
    if expected_output_words != expected_i32.size:
        raise RuntimeError(
            f"Bitstream expects {expected_output_words} output words, "
            f"but fixture provides {expected_i32.size}"
        )

    parameter_buffer = allocate(
        shape=(parameter_packets[0].size,), dtype=np.uint32
    )
    tile_buffer = allocate(shape=(tile_packets[0].size,), dtype=np.uint32)
    recv_buffer = allocate(shape=(expected_i32.size,), dtype=np.int32)

    try:
        accel.write(REG_CTRL, CTRL_SOFT_RESET)
        accel.write(REG_TOTAL_IC, input_channels)

        # For each IC, reuse the same MM2S channel for a parameter packet and
        # one CHW tile packet. Only the final IC produces an S2MM packet.
        for channel, (parameter_words, tile_words) in enumerate(
            zip(parameter_packets, tile_packets)
        ):
            parameter_buffer[:] = parameter_words
            dma.sendchannel.transfer(parameter_buffer)
            accel.write(REG_CTRL, CTRL_LOAD_PARAM)
            dma.sendchannel.wait()

            parameter_status = wait_for_done(accel)
            parameter_errors = int(accel.read(REG_ERROR))
            if parameter_errors != 0:
                raise AssertionError(
                    "Parameter-load error flags are set: "
                    f"0x{parameter_errors:08x}"
                )
            if (parameter_status & (STATUS_PARAM_LOADED | STATUS_DONE)) != (
                STATUS_PARAM_LOADED | STATUS_DONE
            ):
                raise AssertionError(
                    "Parameter load did not complete: "
                    f"status=0x{parameter_status:08x}"
                )

            accel.write(REG_CTRL, CTRL_CLEAR_DONE)

            tile_buffer[:] = tile_words
            final_channel = channel == input_channels - 1
            if final_channel:
                dma.recvchannel.transfer(recv_buffer)

            dma.sendchannel.transfer(tile_buffer)
            accel.write(REG_CTRL, CTRL_RUN_TILE)
            dma.sendchannel.wait()

            if final_channel:
                dma.recvchannel.wait()
                wait_for_done(accel)
            else:
                wait_for_done(accel)
                current_channel = int(accel.read(REG_CURRENT_IC))
                if current_channel != channel + 1:
                    raise AssertionError(
                        f"RTL reports current IC {current_channel}, "
                        f"expected {channel + 1}"
                    )
                if int(accel.read(REG_STREAM_OUT)) != 0:
                    raise AssertionError("Intermediate IC unexpectedly produced output")
                accel.write(REG_CTRL, CTRL_CLEAR_DONE)

        status = int(accel.read(REG_STATUS))
        stream_in = int(accel.read(REG_STREAM_IN))
        stream_out = int(accel.read(REG_STREAM_OUT))
        errors = int(accel.read(REG_ERROR))

        print(f"status=0x{status:08x}")
        print(
            f"stream_in={stream_in}, stream_out={stream_out}, "
            f"errors=0x{errors:08x}"
        )

        if stream_in != tile_packets[-1].size:
            raise AssertionError("Accelerator input-stream count mismatch")
        if stream_out != expected_i32.size:
            raise AssertionError("Accelerator output-stream count mismatch")
        if errors != 0:
            raise AssertionError(f"Accelerator error flags are set: 0x{errors:08x}")
        if (status & (STATUS_IDLE | STATUS_DONE | STATUS_PARAM_LOADED)) != (
            STATUS_IDLE | STATUS_DONE | STATUS_PARAM_LOADED
        ):
            raise AssertionError("Accelerator sticky done bit is not set")
        if status & STATUS_ERROR:
            raise AssertionError(f"Accelerator status reports an error: 0x{status:08x}")

        np.testing.assert_array_equal(np.asarray(recv_buffer), expected_i32)
        print(
            "PASS: PYNQ-Z2 AXI DMA smoke test "
            f"input_channels={input_channels} "
            f"parameters_per_channel={parameter_packets[0].size} "
            f"inputs_per_channel={tile_packets[0].size} "
            f"outputs={expected_i32.size}"
        )
    finally:
        parameter_buffer.close()
        tile_buffer.close()
        recv_buffer.close()


if __name__ == "__main__":
    main()
