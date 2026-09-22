#!/usr/bin/env python3
"""Small local HTTP bridge between Drome and laya-mlx.

The service intentionally uses only Python's standard library for HTTP. The
model is loaded once, warmed up once, and protected by a lock because MLX work
should be serialized inside this small development service.
"""

from __future__ import annotations

import argparse
import json
import os
import threading
import time
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any, Protocol


QUESTIONS = {
    "unsafe": {
        "type": "noul",
        "instructions": (
            "Would this web content likely trigger anxiety or be unsafe because it contains "
            "violence, death, self-harm, crime, disaster, a health crisis, financial doom, "
            "adult content, outrage bait, alarming claims, or high-pressure urgency?"
        ),
    },
    "category": {
        "type": "choice",
        "instructions": "Which content-safety category best describes this web content?",
        "criteria": {
            "safe": "neutral, educational, entertaining, practical, or ordinary content",
            "violence": "violence, death, crime, war, terrorism, or disaster",
            "self_harm": "suicide, self-harm, overdose, or severe mental-health crisis",
            "adult": "nudity, pornography, or explicit sexual content",
            "health_crisis": "alarming disease, outbreak, injury, or medical emergency",
            "financial_stress": "recession, layoffs, bankruptcy, or financial doom",
            "urgency": "high-pressure demand, fear-inducing warning, or act-now language",
            "outrage": "rage bait, scandal, inflammatory claim, or alarming statistic",
        },
    },
}

REASONS = {
    "safe": "Safe content",
    "violence": "Violence or crisis",
    "self_harm": "Self-harm content",
    "adult": "Adult content",
    "health_crisis": "Health crisis",
    "financial_stress": "Financial stress",
    "urgency": "Urgency pressure",
    "outrage": "Outrage or alarm",
}


class Agent(Protocol):
    def predict(self, state: str, questions: dict[str, Any]) -> dict[str, Any]: ...


class SafetyClassifier:
    def __init__(self, agent: Agent, threshold: float = 0.55) -> None:
        self.agent = agent
        self.threshold = threshold
        self._lock = threading.Lock()

    def classify(self, text: str) -> dict[str, Any]:
        started = time.perf_counter()
        with self._lock:
            result = self.agent.predict(text, QUESTIONS)

        answers = result["answers"]
        unsafe_probability = float(answers["unsafe"]["noul"])
        category = str(answers["category"]["choice"])
        safe = unsafe_probability < self.threshold
        reason = "Safe content" if safe else REASONS.get(category, "Sensitive content")
        confidence = max(unsafe_probability, 1.0 - unsafe_probability)

        return {
            "safe": safe,
            "reason": reason,
            "confidence": round(confidence, 4),
            "unsafe_probability": round(unsafe_probability, 4),
            "category": category,
            "latency_ms": round((time.perf_counter() - started) * 1000, 2),
            "model": result.get("model", "laya-mlx"),
        }


def make_handler(classifier: SafetyClassifier) -> type[BaseHTTPRequestHandler]:
    class Handler(BaseHTTPRequestHandler):
        server_version = "DromeLayaMLX/1.0"

        def do_GET(self) -> None:  # noqa: N802
            if self.path == "/health":
                self._json(HTTPStatus.OK, {"status": "ready"})
                return
            self._json(HTTPStatus.NOT_FOUND, {"error": "not_found"})

        def do_POST(self) -> None:  # noqa: N802
            if self.path != "/v1/classify":
                self._json(HTTPStatus.NOT_FOUND, {"error": "not_found"})
                return

            try:
                size = int(self.headers.get("Content-Length", "0"))
                if size <= 0 or size > 16_384:
                    raise ValueError("request body must be between 1 and 16384 bytes")
                payload = json.loads(self.rfile.read(size))
                text = payload.get("text")
                if not isinstance(text, str) or not text.strip():
                    raise ValueError("text must be a non-empty string")
                response = classifier.classify(text[:2_000])
                self._json(HTTPStatus.OK, response)
            except (ValueError, json.JSONDecodeError) as error:
                self._json(HTTPStatus.BAD_REQUEST, {"error": str(error)})
            except Exception as error:  # Keep model failures visible to the client.
                self._json(HTTPStatus.INTERNAL_SERVER_ERROR, {"error": str(error)})

        def log_message(self, format: str, *args: Any) -> None:
            print(f"[laya-mlx] {self.address_string()} {format % args}")

        def _json(self, status: HTTPStatus, payload: dict[str, Any]) -> None:
            body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

    return Handler


def load_classifier() -> SafetyClassifier:
    import laya_mlx as laya

    model = os.getenv("LAYA_MODEL", "aac6fef/laya-mlx")
    threshold = float(os.getenv("LAYA_UNSAFE_THRESHOLD", "0.55"))
    print(f"[laya-mlx] loading {model} (first run may download weights)")
    agent = laya.load(model, dtype="float16", batch_size=16, cache_prompts=True)
    classifier = SafetyClassifier(agent, threshold=threshold)
    classifier.classify("A calm article about gardening and making tea.")
    print("[laya-mlx] model ready")
    return classifier


def main() -> None:
    parser = argparse.ArgumentParser(description="Local Laya MLX backend for Drome")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()

    server = ThreadingHTTPServer((args.host, args.port), make_handler(load_classifier()))
    print(f"[laya-mlx] listening on http://{args.host}:{args.port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
