#!/usr/bin/env python3
"""Build external-agent-readable session digest from data/logs/*.jsonl.

Usage:
  python tools/digest_session.py              # latest session
  python tools/digest_session.py path/to/session.jsonl
  python tools/digest_session.py --json-only  # skip markdown

Outputs alongside the jsonl:
  {session}_digest.md   — human / LLM narrative (primary read)
  {session}_digest.json — structured timeline for tooling
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import sys
from collections import defaultdict
from typing import Any

ROOT = os.path.join(os.path.dirname(__file__), "..")
LOG_DIR = os.path.join(ROOT, "data", "logs")
MEM_DIR = os.path.join(ROOT, "data", "memory")
REL_DIR = os.path.join(ROOT, "data", "relationships")


def latest_log() -> str | None:
    files = sorted(glob.glob(os.path.join(LOG_DIR, "*.jsonl")), key=os.path.getmtime)
    return files[-1] if files else None


def load_jsonl(path: str) -> list[dict[str, Any]]:
    entries: list[dict[str, Any]] = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            entries.append(json.loads(line))
    return entries


def load_summary_for(log_path: str) -> dict[str, Any] | None:
    base = os.path.splitext(log_path)[0]
    summary_path = base + "_summary.json"
    if not os.path.isfile(summary_path):
        return None
    with open(summary_path, encoding="utf-8") as f:
        return json.load(f)


def load_memory(agent_id: str) -> list[dict[str, Any]]:
    path = os.path.join(MEM_DIR, f"{agent_id}.json")
    if not os.path.isfile(path):
        return []
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    return data.get("memories", [])


def load_relationships(agent_id: str) -> dict[str, Any]:
    path = os.path.join(REL_DIR, f"{agent_id}.json")
    if not os.path.isfile(path):
        return {}
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    return data.get("edges", {})


def event_sort_key(entry: dict[str, Any]) -> tuple[int, str]:
    tick = int(entry.get("tick", entry.get("t", -1)))
    event = str(entry.get("event", entry.get("kind", "")))
    return (tick, event)


def build_digest(entries: list[dict[str, Any]], summary: dict[str, Any] | None) -> dict[str, Any]:
    timeline: list[dict[str, Any]] = []
    conversations: list[dict[str, Any]] = []
    item_actions: list[dict[str, Any]] = []
    reflections: list[dict[str, Any]] = []
    plans: list[dict[str, Any]] = []
    world_events: list[dict[str, Any]] = []
    decisions: list[dict[str, Any]] = []
    snapshots: list[dict[str, Any]] = []
    anomalies: list[dict[str, Any]] = []

    for e in entries:
        event = e.get("event")
        if event == "say":
            conversations.append(e)
            timeline.append({"tick": e.get("tick"), "type": "say", "data": e})
        elif event == "action_result":
            kind = str(e.get("kind", ""))
            if kind in ("PICK_UP", "DROP", "USE", "GIVE"):
                item_actions.append(e)
            timeline.append({"tick": e.get("tick"), "type": "action", "data": e})
        elif event == "reflection":
            reflections.append(e)
            timeline.append({"tick": e.get("tick"), "type": "reflection", "data": e})
        elif event == "plan":
            plans.append(e)
            timeline.append({"tick": e.get("tick"), "type": "plan", "data": e})
        elif event == "world_event":
            world_events.append(e)
            timeline.append({"tick": e.get("tick"), "type": "world_event", "data": e})
        elif event == "decision":
            decisions.append(e)
        elif event == "world_snapshot":
            snapshots.append(e)
        elif event == "anomaly":
            anomalies.append(e)

    if summary and summary.get("anomalies"):
        seen = {json.dumps(a, sort_keys=True) for a in anomalies}
        for a in summary["anomalies"]:
            key = json.dumps(a, sort_keys=True)
            if key not in seen:
                anomalies.append(a)
                seen.add(key)

    timeline.sort(key=lambda row: event_sort_key(row.get("data", {})))

    agent_ids: set[str] = set()
    for e in entries:
        for key in ("agent_id", "speaker"):
            val = e.get(key)
            if val:
                agent_ids.add(str(val))
    for snap in snapshots:
        for row in snap.get("agents", []):
            if row.get("id"):
                agent_ids.add(str(row["id"]))

    memory_highlights: dict[str, list[str]] = {}
    for aid in sorted(agent_ids):
        mems = load_memory(aid)
        highlights = [
            f"t{m.get('tick')} [{m.get('category')}] {str(m.get('text', ''))[:120]}"
            for m in mems
            if m.get("category") in ("reflection", "plan", "decision", "action")
        ][-5:]
        if highlights:
            memory_highlights[aid] = highlights

    relationships_end: dict[str, dict[str, Any]] = {}
    for aid in sorted(agent_ids):
        edges = load_relationships(aid)
        if edges:
            relationships_end[aid] = edges

    last_snapshot = snapshots[-1] if snapshots else None

    stats = (summary or {}).get("stats", {})
    heuristic_notes: list[str] = []
    if stats.get("decision_errors", 0) > 0:
        heuristic_notes.append(
            f"{stats.get('decision_errors')} decision error(s) — check anomalies and failed actions."
        )
    say_count = len([c for c in conversations if c.get("ok")])
    if say_count == 0 and len(decisions) > 20:
        heuristic_notes.append("No successful SAY despite many decisions — social loop may be weak.")
    move_only = stats.get("by_action_kind", {}).get("MOVE_TO", 0)
    total_actions = sum(stats.get("by_action_kind", {}).values()) if stats.get("by_action_kind") else 0
    if total_actions > 10 and move_only / max(total_actions, 1) > 0.85:
        heuristic_notes.append("Agents mostly MOVE_TO — plans/items/dialogue underused.")

    return {
        "session_id": (summary or {}).get("session_id"),
        "started_at": (summary or {}).get("started_at"),
        "ended_at": (summary or {}).get("ended_at"),
        "stats": stats,
        "counts": {
            "decisions": len(decisions),
            "conversations": len(conversations),
            "item_actions": len(item_actions),
            "reflections": len(reflections),
            "plans": len(plans),
            "world_events": len(world_events),
            "snapshots": len(snapshots),
            "anomalies": len(anomalies),
        },
        "anomalies": anomalies,
        "heuristic_notes": heuristic_notes,
        "timeline": timeline,
        "conversations": conversations,
        "item_actions": item_actions,
        "reflections": reflections,
        "plans": plans,
        "world_events": world_events,
        "last_snapshot": last_snapshot,
        "memory_highlights": memory_highlights,
        "relationships_end": relationships_end,
    }


def format_action_line(e: dict[str, Any]) -> str:
    kind = e.get("kind", "?")
    agent = e.get("agent_id", "?")
    tick = e.get("tick", "?")
    detail = e.get("detail", "")
    ok = e.get("ok", True)
    mark = "✓" if ok else "✗"
    return f"t{tick} {mark} {agent} {kind}: {detail}"


def format_say_line(e: dict[str, Any]) -> str:
    tick = e.get("tick", "?")
    speaker = e.get("speaker", "?")
    target = e.get("target", "?")
    text = e.get("text", "")
    recipients = e.get("recipients", [])
    heard = ", ".join(recipients) if recipients else "(none)"
    if not e.get("ok", True):
        return f"t{tick} ✗ {speaker} → {target} FAILED: {e.get('error', '')}"
    return f"t{tick} {speaker} → {target}（{heard} 听到）: {text}"


def render_markdown(digest: dict[str, Any], log_path: str) -> str:
    lines: list[str] = []
    lines.append("# Pixel World Session Digest")
    lines.append("")
    lines.append(f"- Log: `{log_path}`")
    if digest.get("session_id"):
        lines.append(f"- Session: `{digest['session_id']}`")
    if digest.get("started_at"):
        lines.append(f"- Started: {digest['started_at']}")
    if digest.get("ended_at"):
        lines.append(f"- Ended: {digest['ended_at']}")
    lines.append("")

    stats = digest.get("stats", {})
    if stats:
        lines.append("## Stats")
        lines.append("")
        lines.append(
            f"- LLM calls: {stats.get('llm_calls', 0)} (errors {stats.get('llm_errors', 0)})"
        )
        lines.append(f"- Tokens: {stats.get('tokens_total', 0):,}")
        lines.append(f"- Decisions: {stats.get('decisions', 0)} (errors {stats.get('decision_errors', 0)})")
        lines.append(f"- Action kinds: {json.dumps(stats.get('by_action_kind', {}), ensure_ascii=False)}")
        lines.append(f"- Per agent: {json.dumps(stats.get('by_agent', {}), ensure_ascii=False)}")
        lines.append("")

    counts = digest.get("counts", {})
    lines.append("## Event counts")
    lines.append("")
    for k, v in counts.items():
        lines.append(f"- {k}: {v}")
    lines.append("")

    if digest.get("heuristic_notes"):
        lines.append("## Quick observations (heuristic)")
        lines.append("")
        for note in digest["heuristic_notes"]:
            lines.append(f"- {note}")
        lines.append("")

    anomalies = digest.get("anomalies", [])
    lines.append("## Anomalies")
    lines.append("")
    if not anomalies:
        lines.append("（无自动标记异常）")
    else:
        for a in anomalies:
            lines.append(
                f"- t{a.get('tick', '?')} [{a.get('kind', a.get('event', '?'))}] "
                f"{a.get('agent_id', '')}: {a.get('detail', '')}"
            )
    lines.append("")

    conversations = digest.get("conversations", [])
    lines.append("## Conversations")
    lines.append("")
    if not conversations:
        lines.append("（本局无对话）")
    else:
        for c in conversations:
            lines.append(f"- {format_say_line(c)}")
    lines.append("")

    items = digest.get("item_actions", [])
    lines.append("## Items")
    lines.append("")
    if not items:
        lines.append("（无物品相关行动）")
    else:
        for e in items:
            lines.append(f"- {format_action_line(e)}")
    lines.append("")

    reflections = digest.get("reflections", [])
    lines.append("## Reflections")
    lines.append("")
    if not reflections:
        lines.append("（无反思记录）")
    else:
        for r in reflections:
            text = str(r.get("text", "")).replace("\n", " ")[:300]
            lines.append(f"- t{r.get('tick')} {r.get('agent_id')}: {text}")
    lines.append("")

    plans = digest.get("plans", [])
    lines.append("## Plans")
    lines.append("")
    if not plans:
        lines.append("（无计划记录）")
    else:
        for p in plans:
            steps = p.get("steps", [])
            step_preview = "; ".join(str(s) for s in steps[:5])
            lines.append(f"- t{p.get('tick')} {p.get('agent_id')}: {step_preview}")
    lines.append("")

    world_events = digest.get("world_events", [])
    lines.append("## World events")
    lines.append("")
    if not world_events:
        lines.append("（无）")
    else:
        for w in world_events:
            lines.append(f"- t{w.get('tick')} [{w.get('event_id')}]: {w.get('text')}")
    lines.append("")

    snap = digest.get("last_snapshot")
    lines.append("## Final positions (last snapshot)")
    lines.append("")
    if not snap:
        lines.append("（无快照 — 可调大 observability.snapshot_interval_ticks）")
    else:
        lines.append(f"Tick {snap.get('tick')}:")
        for row in snap.get("agents", []):
            inv = row.get("inventory", [])
            inv_s = ",".join(inv) if inv else "空"
            lines.append(
                f"- {row.get('display_name', row.get('id'))} @ ({row.get('tile')}) "
                f"{row.get('region', '')} | {row.get('state')} | 背包={inv_s}"
            )
    lines.append("")

    rel = digest.get("relationships_end", {})
    if rel:
        lines.append("## Relationships (end state)")
        lines.append("")
        for aid, edges in rel.items():
            parts = []
            for other, e in sorted(edges.items()):
                parts.append(
                    f"{other}(熟={float(e.get('familiarity', 0)):.2f}, "
                    f"好={float(e.get('affinity', 0)):.2f})"
                )
            if parts:
                lines.append(f"- {aid}: {', '.join(parts)}")
        lines.append("")

    mem_h = digest.get("memory_highlights", {})
    if mem_h:
        lines.append("## Memory highlights (from data/memory)")
        lines.append("")
        for aid, hl in mem_h.items():
            lines.append(f"### {aid}")
            for line in hl:
                lines.append(f"- {line}")
            lines.append("")

    lines.append("## Timeline (merged)")
    lines.append("")
    for row in digest.get("timeline", []):
        tick = row.get("tick")
        typ = row.get("type")
        data = row.get("data", {})
        if typ == "say":
            lines.append(f"- {format_say_line(data)}")
        elif typ == "action":
            lines.append(f"- {format_action_line(data)}")
        elif typ == "reflection":
            text = str(data.get("text", "")).replace("\n", " ")[:120]
            lines.append(f"- t{tick} 反思 {data.get('agent_id')}: {text}")
        elif typ == "plan":
            steps = data.get("steps", [])
            lines.append(f"- t{tick} 计划 {data.get('agent_id')}: {steps[0] if steps else ''}")
        elif typ == "world_event":
            lines.append(f"- t{tick} 世界 [{data.get('event_id')}]: {data.get('text')}")
    lines.append("")
    lines.append("---")
    lines.append("_Generated by tools/digest_session.py — feed this file to an external agent for review._")
    return "\n".join(lines)


def write_digest(log_path: str, write_md: bool = True, write_json: bool = True) -> tuple[str | None, str | None]:
    entries = load_jsonl(log_path)
    summary = load_summary_for(log_path)
    digest = build_digest(entries, summary)
    base = os.path.splitext(log_path)[0]
    md_path = base + "_digest.md"
    json_path = base + "_digest.json"

    if write_json:
        with open(json_path, "w", encoding="utf-8") as f:
            json.dump(digest, f, ensure_ascii=False, indent=2)
    if write_md:
        with open(md_path, "w", encoding="utf-8") as f:
            f.write(render_markdown(digest, log_path))

    return (md_path if write_md else None, json_path if write_json else None)


def main() -> int:
    parser = argparse.ArgumentParser(description="Build session digest for external agent review")
    parser.add_argument("log_path", nargs="?", help="Path to session .jsonl (default: latest)")
    parser.add_argument("--json-only", action="store_true", help="Only write digest JSON")
    parser.add_argument("--md-only", action="store_true", help="Only write digest Markdown")
    args = parser.parse_args()

    log_path = args.log_path or latest_log()
    if not log_path or not os.path.isfile(log_path):
        print("No log file found. Run the game first to create data/logs/*.jsonl")
        return 1

    write_md = not args.json_only
    write_json = not args.md_only
    md_path, json_path = write_digest(log_path, write_md=write_md, write_json=write_json)

    print(f"Source: {log_path}")
    if md_path:
        print(f"Digest MD:   {md_path}")
    if json_path:
        print(f"Digest JSON: {json_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
