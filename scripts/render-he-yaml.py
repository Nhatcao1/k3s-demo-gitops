#!/usr/bin/env python3
"""Render ${NAME} placeholders in one tracked Kubernetes YAML template."""

from __future__ import annotations

import os
from pathlib import Path
import re
import sys


PLACEHOLDER = re.compile(r"\$\{([A-Z][A-Z0-9_]*)\}")


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(f"Usage: {sys.argv[0]} <template.yaml>")

    template_path = Path(sys.argv[1])
    template = template_path.read_text(encoding="utf-8")
    required = sorted(set(PLACEHOLDER.findall(template)))
    missing = [name for name in required if not os.environ.get(name)]
    if missing:
        raise SystemExit(
            "Missing template environment variables: " + ", ".join(missing)
        )

    rendered = PLACEHOLDER.sub(lambda match: os.environ[match.group(1)], template)
    sys.stdout.write(rendered)


if __name__ == "__main__":
    main()
