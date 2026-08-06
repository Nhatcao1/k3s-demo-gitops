#!/usr/bin/env python3
"""Resolve one public Docker Hub tag to an immutable image digest."""

from __future__ import annotations

import json
import re
import sys
from urllib.parse import quote
from urllib.request import urlopen


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(f"Usage: {sys.argv[0]} <docker.io/repository> <tag>")

    repository = sys.argv[1].removeprefix("docker.io/")
    tag = sys.argv[2]
    if not repository or "/" not in repository:
        raise SystemExit("Docker Hub repository must include an owner and name")
    if not re.fullmatch(r"[0-9A-Za-z._-]+", tag):
        raise SystemExit("Docker tag contains unsupported characters")

    url = (
        "https://hub.docker.com/v2/repositories/"
        f"{quote(repository, safe='/')}/tags/{quote(tag, safe='')}"
    )
    with urlopen(url, timeout=30) as response:
        payload = json.load(response)
    digest = payload.get("digest")
    if not isinstance(digest, str) or not re.fullmatch(r"sha256:[0-9a-f]{64}", digest):
        raise SystemExit("Docker Hub returned no valid image digest")

    print(f"docker.io/{repository}@{digest}")


if __name__ == "__main__":
    main()
