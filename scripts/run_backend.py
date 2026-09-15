"""Run the synthetic companion API on loopback only."""

from __future__ import annotations

import argparse

import _bootstrap  # noqa: F401
import uvicorn


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    uvicorn.run("kof5_tts.api:app", host="127.0.0.1", port=args.port)


if __name__ == "__main__":
    main()
