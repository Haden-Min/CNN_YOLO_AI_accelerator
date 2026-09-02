#!/usr/bin/env python3
"""Bit-exact reference for fused LINEAR/LEAKY_RELU requantization."""

from __future__ import annotations

import argparse
import random


MODE_LINEAR = 0
MODE_LEAKY_RELU = 1
INT8_MIN = -128
INT8_MAX = 127


def round_shift_away_from_zero(value: int, shift: int) -> int:
    """Round value / 2**shift to nearest, exact halves away from zero."""
    if not 0 <= shift <= 63:
        raise ValueError("shift must be in [0, 63]")
    if shift == 0:
        return value

    magnitude = abs(value)
    rounded = (magnitude + (1 << (shift - 1))) >> shift
    return -rounded if value < 0 else rounded


def activation_requant_int8(
    acc: int,
    activation_mode: int,
    multiplier_pos: int,
    shift_pos: int,
    multiplier_neg: int,
    shift_neg: int,
    zero_point: int = 0,
) -> tuple[int, bool, bool]:
    """Return (signed_int8_output, clipped, mode_error)."""
    if not -(1 << 31) <= acc < (1 << 31):
        raise ValueError("acc must fit signed INT32")

    mode_error = activation_mode not in (MODE_LINEAR, MODE_LEAKY_RELU)
    use_negative = activation_mode == MODE_LEAKY_RELU and acc < 0

    if use_negative:
        multiplier = multiplier_neg
        shift = shift_neg
    else:
        multiplier = multiplier_pos
        shift = shift_pos

    product = acc * multiplier
    scaled = round_shift_away_from_zero(product, shift)
    shifted = scaled + zero_point
    clipped = shifted < INT8_MIN or shifted > INT8_MAX
    output = max(INT8_MIN, min(INT8_MAX, shifted))
    return output, clipped, mode_error


def self_test(iterations: int, seed: int) -> None:
    directed = [
        # acc, mode, m_pos, s_pos, m_neg, s_neg, zp, expected
        (10, MODE_LINEAR, 1, 0, 99, 0, 0, 10),
        (-10, MODE_LINEAR, 1, 0, 99, 0, 0, -10),
        (10, MODE_LEAKY_RELU, 1, 0, 1, 1, 0, 10),
        (-3, MODE_LEAKY_RELU, 1, 0, 1, 1, 0, -2),
        (-100, MODE_LEAKY_RELU, 1, 0, 3277, 15, 0, -10),
        (1000, MODE_LINEAR, 1, 0, 1, 0, 0, 127),
        (-1000, MODE_LINEAR, 1, 0, 1, 0, 0, -128),
        (10, MODE_LINEAR, 1, 1, 1, 1, 3, 8),
    ]
    for vector in directed:
        *args, expected = vector
        got, _, _ = activation_requant_int8(*args)
        assert got == expected, (vector, got)

    rng = random.Random(seed)
    for _ in range(iterations):
        acc = rng.randint(-(1 << 31), (1 << 31) - 1)
        mode = rng.randrange(4)
        multiplier_pos = rng.randint(0, (1 << 20) - 1)
        multiplier_neg = rng.randint(0, (1 << 20) - 1)
        shift_pos = rng.randrange(64)
        shift_neg = rng.randrange(64)
        zero_point = rng.randint(-256, 255)
        output, _, mode_error = activation_requant_int8(
            acc,
            mode,
            multiplier_pos,
            shift_pos,
            multiplier_neg,
            shift_neg,
            zero_point,
        )
        assert INT8_MIN <= output <= INT8_MAX
        assert mode_error == (mode not in (MODE_LINEAR, MODE_LEAKY_RELU))

    print(
        "PASS: activation_requant_reference "
        f"directed={len(directed)} random={iterations} seed={seed}"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--iterations", type=int, default=10_000)
    parser.add_argument("--seed", type=int, default=20260820)
    args = parser.parse_args()

    if args.self_test:
        self_test(args.iterations, args.seed)
    else:
        parser.error("use --self-test")


if __name__ == "__main__":
    main()
