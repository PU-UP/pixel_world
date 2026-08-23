#!/usr/bin/env python3
"""Summarize data/logs + memory + relationships for maintenance.

For a full narrative digest (external agent review), run:
  python tools/digest_session.py
"""
import json
import glob
import os
import subprocess
import sys
from collections import defaultdict

ROOT = os.path.join(os.path.dirname(__file__), "..")
LOG_DIR = os.path.join(ROOT, "data", "logs")
MEM_DIR = os.path.join(ROOT, "data", "memory")
REL_DIR = os.path.join(ROOT, "data", "relationships")


def latest_log():
    files = sorted(glob.glob(os.path.join(LOG_DIR, "*.jsonl")), key=os.path.getmtime)
    return files[-1] if files else None


def latest_summary_for(log_path: str):
    base = os.path.splitext(log_path)[0]
    summary = base + "_summary.json"
    return summary if os.path.isfile(summary) else None


def summarize_log(path: str) -> None:
    entries = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                entries.append(json.loads(line))

    decisions = [e for e in entries if e.get("event") in (None, "decision") and "parsed_action" in e]
    llm_calls = [e for e in entries if e.get("event") == "llm_call"]

    by_agent: dict = defaultdict(list)
    by_kind: dict = defaultdict(int)
    errors = 0
    for e in decisions:
        by_agent[e.get("agent_id", "?")].append(e)
        act = e.get("parsed_action") or {}
        by_kind[act.get("kind", "(none)")] += 1
        if e.get("result") != "ok":
            errors += 1

    print(f"Decision log entries: {len(decisions)}")
    print(f"Action kinds: {dict(by_kind)}")
    print(f"Failed decisions: {errors}")

    if llm_calls:
        pt = sum(int(e.get("prompt_tokens", 0)) for e in llm_calls)
        ct = sum(int(e.get("completion_tokens", 0)) for e in llm_calls)
        tt = sum(int(e.get("total_tokens", 0)) for e in llm_calls)
        by_type: dict = defaultdict(int)
        for e in llm_calls:
            by_type[e.get("request_type", "?")] += 1
        print(f"LLM calls logged: {len(llm_calls)} | by type: {dict(by_type)}")
        print(f"Tokens — prompt: {pt:,}  completion: {ct:,}  total: {tt:,}")
    else:
        est = len(decisions) * 900
        print(
            "LLM token stats: not recorded in this session "
            f"(rough estimate ~{est:,} tokens if ~900/decision)"
        )
    print()

    for aid in sorted(by_agent):
        evs = by_agent[aid]
        print(f"--- {aid} ({len(evs)} logged decisions) ---")
        for e in evs:
            tick = e.get("tick")
            act = e.get("parsed_action") or {}
            kind = act.get("kind", "?")
            params = act.get("params", {})
            res = e.get("result")
            err = e.get("error", "")
            extra = f" ({err})" if err else ""
            print(f"  t{tick} {kind} {params} -> {res}{extra}")
        print()


def print_summary_file(path: str) -> None:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    stats = data.get("stats", {})
    print("=== Session summary file ===")
    print(path)
    print(f"Started: {data.get('started_at')}  Ended: {data.get('ended_at')}")
    print(
        f"LLM calls: {stats.get('llm_calls', 0)}  errors: {stats.get('llm_errors', 0)}  "
        f"tokens total: {stats.get('tokens_total', 0):,}"
    )
    print(f"By request type: {stats.get('by_request_type', {})}")
    print(f"By action kind: {stats.get('by_action_kind', {})}")
    print(f"Per agent: {json.dumps(stats.get('by_agent', {}), ensure_ascii=False)}")
    print()


def summarize_memory() -> None:
    print("=== Memory snapshots ===")
    for fn in sorted(glob.glob(os.path.join(MEM_DIR, "*.json"))):
        name = os.path.basename(fn).replace(".json", "")
        if name == "player":
            continue
        with open(fn, encoding="utf-8") as f:
            data = json.load(f)
        mems = data.get("memories", [])
        cats: dict = defaultdict(int)
        for m in mems:
            cats[m.get("category", "?")] += 1
        print(f"{name}: {len(mems)} entries | {dict(cats)}")
        highlights = [
            m
            for m in mems
            if m.get("category") in ("action", "decision", "plan", "reflection")
        ][-2:]
        for m in highlights:
            text = str(m.get("text", ""))[:100]
            print(f"  t{m.get('tick')} [{m.get('category')}] {text}")
        print()


def summarize_relationships() -> None:
    print("=== Relationships ===")
    for fn in sorted(glob.glob(os.path.join(REL_DIR, "*.json"))):
        name = os.path.basename(fn).replace(".json", "")
        with open(fn, encoding="utf-8") as f:
            data = json.load(f)
        edges = data.get("edges", {})
        if not edges:
            print(f"{name}: (none yet)")
            continue
        parts = []
        for other, e in sorted(edges.items()):
            parts.append(
                f"{other}(fam={float(e.get('familiarity', 0)):.2f}, aff={float(e.get('affinity', 0)):.2f})"
            )
        print(f"{name}: {', '.join(parts)}")


if __name__ == "__main__":
    path = latest_log()
    if not path:
        print("No log files found.")
    else:
        print("=== Latest session ===")
        print(path)
        print()
        summary = latest_summary_for(path)
        if summary:
            print_summary_file(summary)
            anomalies = summary.get("anomalies", [])
            if anomalies:
                print("=== Runtime anomalies ===")
                for a in anomalies:
                    print(
                        f"  t{a.get('tick')} [{a.get('kind')}] "
                        f"{a.get('agent_id')}: {a.get('detail')}"
                    )
                print()
        summarize_log(path)
    summarize_memory()
    summarize_relationships()
    digest_tool = os.path.join(os.path.dirname(__file__), "digest_session.py")
    if path and os.path.isfile(digest_tool):
        print("=== Generating digest ===")
        subprocess.run([sys.executable, digest_tool, path], check=False)
