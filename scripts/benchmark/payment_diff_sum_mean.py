#!/usr/bin/env python3
"""Run SUM against the deployed evaluator service."""

from __future__ import annotations

import sys

from service_benchmark import main


if __name__ == "__main__":
    if "--workload" not in sys.argv:
        sys.argv[1:1] = ["--workload", "sum"]
    main()
