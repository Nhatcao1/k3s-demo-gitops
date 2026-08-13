#!/usr/bin/env python3
"""Trusted client for small, real /v1/evaluate correctness tests."""

from __future__ import annotations

import base64
import binascii
import json
import math
import os
from pathlib import Path
import time
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit, urlunsplit
from urllib.request import Request, urlopen

LEFT = [1.25, -2.0, 3.5, 4.0]
RIGHT = [0.75, 5.0, -1.5, 2.0]
BINARY_OPERATIONS = {"add", "subtract", "multiply"}
MULTIPLICATION_KEY_OPERATIONS = {"multiply", "square", "variance"}
ROTATION_KEY_OPERATIONS = {"sum", "mean", "variance"}
REDUCTION_OPERATIONS = {"sum", "mean", "variance"}
OPERATIONS = (
    "add",
    "subtract",
    "multiply",
    "square",
    "sum",
    "mean",
    "variance",
)


def expected_values(operation: str) -> list[float]:
    """Return the small plaintext oracle for one operation."""
    if operation == "add":
        return [a + b for a, b in zip(LEFT, RIGHT, strict=True)]
    if operation == "subtract":
        return [a - b for a, b in zip(LEFT, RIGHT, strict=True)]
    if operation == "multiply":
        return [a * b for a, b in zip(LEFT, RIGHT, strict=True)]
    if operation == "square":
        return [value * value for value in LEFT]
    if operation == "sum":
        return [sum(LEFT)]
    if operation == "mean":
        return [sum(LEFT) / len(LEFT)]
    if operation == "variance":
        mean = sum(LEFT) / len(LEFT)
        return [sum((value - mean) ** 2 for value in LEFT) / len(LEFT)]
    raise ValueError(f"unsupported operation: {operation}")


def endpoint(base_url: str, path: str) -> str:
    parsed = urlsplit(base_url)
    if not parsed.scheme or not parsed.netloc:
        raise ValueError(f"invalid evaluator URL: {base_url}")
    return urlunsplit((parsed.scheme, parsed.netloc, path, "", ""))


def get_json(url: str, timeout: float) -> dict[str, Any]:
    try:
        with urlopen(url, timeout=timeout) as response:
            payload = json.load(response)
    except (HTTPError, URLError, TimeoutError) as error:
        raise RuntimeError(f"GET {url} failed: {error}") from error
    if not isinstance(payload, dict):
        raise RuntimeError(f"GET {url} did not return a JSON object")
    return payload


def post_json(
    url: str, payload: dict[str, Any], timeout: float
) -> dict[str, Any]:
    request = Request(
        url,
        data=json.dumps(payload, separators=(",", ":")).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urlopen(request, timeout=timeout) as response:
            result = json.load(response)
    except HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(
            f"POST {url} returned HTTP {error.code}: {detail}"
        ) from error
    except (URLError, TimeoutError) as error:
        raise RuntimeError(f"POST {url} failed: {error}") from error
    if not isinstance(result, dict):
        raise RuntimeError("evaluator response is not a JSON object")
    return result


def serialize(openfhe: Any, path: Path, value: Any) -> None:
    if not openfhe.SerializeToFile(str(path), value, openfhe.BINARY):
        raise RuntimeError(f"could not serialize {path.name}")


def encode_file(path: Path) -> str:
    return base64.b64encode(path.read_bytes()).decode("ascii")


def artifact_directory(operation: str, backend: str) -> Path:
    root = Path(os.getenv("HE_EVALUATE_API_ARTIFACT_DIR", "/he-artifacts"))
    run_id = os.getenv("HE_EVALUATE_API_RUN_ID", str(int(time.time())))
    path = root / backend / operation / run_id
    path.mkdir(parents=True, exist_ok=False)
    return path


def build_request(
    operation: str,
    artifacts: Path,
    public_key_required: bool,
) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "operation": operation,
        "context": encode_file(artifacts / "context.bin"),
        "ciphertext_a": encode_file(artifacts / "ciphertext-a.bin"),
        "request_id": f"evaluate-api-{operation}",
    }
    if public_key_required:
        payload["public_key"] = encode_file(artifacts / "public-key.bin")
    if operation in BINARY_OPERATIONS:
        payload["ciphertext_b"] = encode_file(
            artifacts / "ciphertext-b.bin"
        )
    if operation in MULTIPLICATION_KEY_OPERATIONS:
        field = (
            "multiplication_keys"
            if operation == "variance"
            else "evaluation_keys"
        )
        payload[field] = encode_file(artifacts / "multiplication-keys.bin")
    if operation in ROTATION_KEY_OPERATIONS:
        field = "rotation_keys" if operation == "variance" else "evaluation_keys"
        payload[field] = encode_file(artifacts / "rotation-keys.bin")
    if operation in REDUCTION_OPERATIONS:
        payload["valid_count"] = len(LEFT)
    return payload


def run_operation(operation: str) -> dict[str, Any]:
    """Encrypt, call the real evaluator, persist ciphertexts, and decrypt."""
    if operation not in OPERATIONS:
        raise ValueError(f"unsupported operation: {operation}")
    backend = os.getenv("HE_EVALUATE_API_BACKEND", "cpu").lower()
    if backend not in {"cpu", "gpu"}:
        raise ValueError("HE_EVALUATE_API_BACKEND must be cpu or gpu")
    evaluator_url = os.environ["HE_EVALUATE_API_URL"]
    timeout = float(os.getenv("HE_EVALUATE_API_TIMEOUT_SECONDS", "600"))
    tolerance = float(os.getenv("HE_EVALUATE_API_TOLERANCE", "0.001"))

    import openfhe
    from openfhe_cpu.runtime import create_trial_context_and_keys

    artifacts = artifact_directory(operation, backend)
    context, keys = create_trial_context_and_keys(openfhe)
    left_ciphertext = context.Encrypt(
        keys.publicKey, context.MakeCKKSPackedPlaintext(LEFT)
    )
    right_ciphertext = context.Encrypt(
        keys.publicKey, context.MakeCKKSPackedPlaintext(RIGHT)
    )

    serialize(openfhe, artifacts / "context.bin", context)
    serialize(openfhe, artifacts / "public-key.bin", keys.publicKey)
    serialize(openfhe, artifacts / "ciphertext-a.bin", left_ciphertext)
    serialize(openfhe, artifacts / "ciphertext-b.bin", right_ciphertext)
    if not context.SerializeEvalMultKey(
        str(artifacts / "multiplication-keys.bin"), openfhe.BINARY
    ):
        raise RuntimeError("could not serialize multiplication keys")
    if not context.SerializeEvalAutomorphismKey(
        str(artifacts / "rotation-keys.bin"), openfhe.BINARY
    ):
        raise RuntimeError("could not serialize rotation keys")

    capabilities = get_json(
        endpoint(evaluator_url, "/v1/capabilities"), timeout
    )
    advertised = capabilities.get("operations")
    if not isinstance(advertised, list) or operation not in advertised:
        raise RuntimeError(f"{backend} evaluator does not advertise {operation}")
    public_key_required = bool(
        capabilities.get("public_key_required_by_api", False)
    )
    request_payload = build_request(
        operation, artifacts, public_key_required
    )
    response = post_json(
        endpoint(evaluator_url, "/v1/evaluate"), request_payload, timeout
    )
    encoded_result = response.get("ciphertext")
    if not isinstance(encoded_result, str) or not encoded_result:
        raise RuntimeError("evaluator response has no ciphertext")
    try:
        result_bytes = base64.b64decode(encoded_result, validate=True)
    except (binascii.Error, ValueError) as error:
        raise RuntimeError("evaluator returned invalid base64 ciphertext") from error
    result_path = artifacts / "result-ciphertext.bin"
    result_path.write_bytes(result_bytes)
    result_ciphertext, ok = openfhe.DeserializeCiphertext(
        str(result_path), openfhe.BINARY
    )
    if not ok:
        raise RuntimeError("trusted client could not deserialize result ciphertext")

    output_length = 1 if operation in REDUCTION_OPERATIONS else len(LEFT)
    plaintext = context.Decrypt(keys.secretKey, result_ciphertext)
    plaintext.SetLength(output_length)
    actual = [
        float(value)
        for value in plaintext.GetRealPackedValue()[:output_length]
    ]
    expected = expected_values(operation)
    maximum_error = max(
        abs(got - wanted)
        for got, wanted in zip(actual, expected, strict=True)
    )
    passed = math.isfinite(maximum_error) and maximum_error <= tolerance
    result = {
        "status": "PASS" if passed else "FAIL",
        "backend": backend,
        "operation": operation,
        "left": LEFT,
        "right": RIGHT if operation in BINARY_OPERATIONS else None,
        "expected": expected,
        "decrypted": actual,
        "maximum_absolute_error": maximum_error,
        "tolerance": tolerance,
        "evaluation_seconds": response.get("evaluation_seconds"),
        "result_ciphertext_bytes": len(result_bytes),
        "artifact_directory": str(artifacts),
        "secret_key_sent_to_evaluator": False,
        "plaintext_sent_to_evaluator": False,
    }
    # Keep plaintext expected/decrypted values in the short-lived Job log, not
    # beside persistent ciphertext artifacts on the PVC.
    artifact_record = {
        name: result[name]
        for name in (
            "status",
            "backend",
            "operation",
            "maximum_absolute_error",
            "tolerance",
            "evaluation_seconds",
            "result_ciphertext_bytes",
            "secret_key_sent_to_evaluator",
            "plaintext_sent_to_evaluator",
        )
    }
    (artifacts / "result.json").write_text(
        json.dumps(artifact_record, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(result, indent=2), flush=True)
    if not passed:
        raise RuntimeError(
            f"{backend} {operation} error {maximum_error} exceeds {tolerance}"
        )
    return result


def main_for(operation: str) -> None:
    try:
        run_operation(operation)
    except Exception as error:
        print(
            json.dumps(
                {
                    "status": "ERROR",
                    "operation": operation,
                    "error_type": type(error).__name__,
                    "error_message": str(error),
                },
                indent=2,
            ),
            flush=True,
        )
        raise
