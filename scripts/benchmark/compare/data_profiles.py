#!/usr/bin/env python3
"""Shared deterministic CKKS benchmark data profiles."""

from __future__ import annotations

import random
from collections.abc import Iterator


INPUT_BOUND = 40_000
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
}
DATA_PROFILES = {**RANDOM_DATA_PROFILES, **SEQUENTIAL_DATA_PROFILES}


def expand_profiles(requested: list[str]) -> list[str]:
    if "all" in requested:
        if requested != ["all"]:
            raise ValueError("use --data-profiles all by itself")
        return list(RANDOM_DATA_PROFILES)
    if "stress" in requested:
        if requested != ["stress"]:
            raise ValueError("use --data-profiles stress by itself")
        return list(SEQUENTIAL_DATA_PROFILES)
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
    if profile in SEQUENTIAL_DATA_PROFILES:
        # Both A and B deliberately use the same exact 1..40000 cycle. A
        # 10-million-row file therefore repeats a bounded, reviewable input
        # sequence instead of drawing ten million random values.
        for index in range(count):
            yield multiplier * float(index % INPUT_BOUND + 1)
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
