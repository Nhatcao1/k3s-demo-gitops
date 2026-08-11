#!/usr/bin/env python3
"""Shared deterministic CKKS benchmark data profiles."""

from __future__ import annotations

import random
from collections.abc import Iterator


INPUT_BOUND = 40_000
STRESS_INPUT_BOUND = 1_000_000_000
RANDOM_DATA_PROFILES: dict[str, tuple[str, int]] = {
    "positive_integer": ("positive", 0),
    "negative_integer": ("negative", 0),
    "positive_decimal_1": ("positive", 1),
    "negative_decimal_1": ("negative", 1),
    "positive_decimal_2": ("positive", 2),
    "negative_decimal_2": ("negative", 2),
    "positive_decimal_3": ("positive", 3),
    "negative_decimal_3": ("negative", 3),
    "positive_decimal_6": ("positive", 6),
    "negative_decimal_6": ("negative", 6),
}
SEQUENTIAL_DATA_PROFILES: dict[str, tuple[str, int]] = {
    "sequential_positive_integer": ("positive", 0),
    "sequential_negative_integer": ("negative", 0),
    "sequential_positive_decimal_1": ("positive", 1),
    "sequential_negative_decimal_1": ("negative", 1),
    "sequential_positive_decimal_2": ("positive", 2),
    "sequential_negative_decimal_2": ("negative", 2),
    "sequential_positive_decimal_3": ("positive", 3),
    "sequential_negative_decimal_3": ("negative", 3),
    "sequential_positive_decimal_6": ("positive", 6),
    "sequential_negative_decimal_6": ("negative", 6),
}
STRESS_DATA_PROFILES: dict[str, tuple[str, int]] = {
    "stress_positive_integer_1b": ("positive", 0),
    "stress_negative_integer_1b": ("negative", 0),
}
DATA_PROFILES = {
    **RANDOM_DATA_PROFILES,
    **SEQUENTIAL_DATA_PROFILES,
    **STRESS_DATA_PROFILES,
}


def profile_input_bound(profile: str) -> int:
    return STRESS_INPUT_BOUND if profile in STRESS_DATA_PROFILES else INPUT_BOUND


def expand_profiles(requested: list[str]) -> list[str]:
    if "all" in requested:
        if requested != ["all"]:
            raise ValueError("use --data-profiles all by itself")
        return list(RANDOM_DATA_PROFILES)
    if "stress" in requested:
        if requested != ["stress"]:
            raise ValueError("use --data-profiles stress by itself")
        return list(STRESS_DATA_PROFILES)
    invalid = sorted(set(requested) - set(DATA_PROFILES))
    if invalid:
        raise ValueError(f"invalid data profiles: {', '.join(invalid)}")
    return list(dict.fromkeys(requested))


def values(profile: str, count: int, seed: int, vector: str) -> Iterator[float]:
    """Yield one stable vector without retaining it in memory."""
    if vector not in {"a", "b"}:
        raise ValueError("vector must be a or b")
    sign, decimal_places = DATA_PROFILES[profile]
    multiplier = -1.0 if sign == "negative" else 1.0
    if profile in STRESS_DATA_PROFILES:
        for index in range(count):
            yield multiplier * float(index % STRESS_INPUT_BOUND + 1)
        return
    if profile in SEQUENTIAL_DATA_PROFILES:
        # The integer part follows the exact 1..40000 cycle. Decimal profiles
        # add deterministic seeded fractional digits; A and B use independent
        # fractional streams. Keep the 40000 endpoint fractional part at zero
        # so every generated value remains inside the documented bound.
        source = random.Random(f"{seed}:{profile}:{vector}:fraction")
        scale = 10**decimal_places
        prefix_limit = 10 ** max(decimal_places - 1, 0)
        for index in range(count):
            whole = index % INPUT_BOUND + 1
            if decimal_places == 0 or whole == INPUT_BOUND:
                yield multiplier * float(whole)
                continue
            fractional_prefix = source.randrange(prefix_limit)
            fractional_last_digit = source.randint(1, 9)
            fraction = fractional_prefix * 10 + fractional_last_digit
            yield multiplier * (whole + fraction / scale)
        return

    source = random.Random(f"{seed}:{profile}:{vector}")
    if decimal_places == 0:
        for _ in range(count):
            yield multiplier * source.randint(1, INPUT_BOUND)
        return

    scale = 10**decimal_places
    prefix_limit = 10 ** (decimal_places - 1)
    for _ in range(count):
        whole = source.randrange(INPUT_BOUND)
        fractional_prefix = source.randrange(prefix_limit)
        fractional_last_digit = source.randint(1, 9)
        fraction = fractional_prefix * 10 + fractional_last_digit
        yield multiplier * (whole + fraction / scale)
