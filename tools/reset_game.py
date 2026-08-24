#!/usr/bin/env python3
"""Wipe runtime game state (memory + relationships + world save). Same as in-game Ctrl+R data wipe.

Usage:
  python tools/reset_game.py           # memory + relationships + goals + world save
  python tools/reset_game.py --logs    # also delete data/logs/*
"""
from __future__ import annotations

import argparse
import glob
import os
import sys

ROOT = os.path.join(os.path.dirname(__file__), "..")
DATA = os.path.join(ROOT, "data")


def wipe_json_in(dir_name: str) -> int:
    dir_path = os.path.join(DATA, dir_name)
    if not os.path.isdir(dir_path):
        os.makedirs(dir_path, exist_ok=True)
        return 0
    removed = 0
    for path in glob.glob(os.path.join(dir_path, "*.json")):
        os.remove(path)
        removed += 1
        print(f"removed {path}")
    return removed


def wipe_saves() -> int:
    return wipe_json_in("saves")


def wipe_logs() -> int:
    log_dir = os.path.join(DATA, "logs")
    if not os.path.isdir(log_dir):
        return 0
    removed = 0
    for path in glob.glob(os.path.join(log_dir, "*")):
        if os.path.isfile(path):
            os.remove(path)
            removed += 1
            print(f"removed {path}")
    return removed


def main() -> int:
    parser = argparse.ArgumentParser(description="Reset Pixel World persisted runtime data")
    parser.add_argument(
        "--logs",
        action="store_true",
        help="Also delete session logs (jsonl, summary, digest)",
    )
    args = parser.parse_args()

    mem = wipe_json_in("memory")
    rel = wipe_json_in("relationships")
    goals = wipe_json_in("goals")
    saves = wipe_saves()
    logs = wipe_logs() if args.logs else 0

    print()
    print(
        f"Reset complete: memory={mem}, relationships={rel}, goals={goals}, "
        f"saves={saves}, log_files={logs}"
    )
    print("Start Godot and press F5 — agents spawn fresh (F3 for agent mode).")
    if not args.logs:
        print("Logs kept. Use --logs to wipe session history too.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
