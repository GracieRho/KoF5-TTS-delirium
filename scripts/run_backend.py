"""Serve the Favilium voice workspace on the loopback interface."""

import argparse
from pathlib import Path

import uvicorn


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8765)
    arguments = parser.parse_args()
    uvicorn.run(
        "app:app", host="127.0.0.1", port=arguments.port,
        app_dir=str(Path(__file__).resolve().parents[1]),
    )
