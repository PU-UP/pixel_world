extends Node
class_name ObservabilityLogger
##
## 维护向观测日志 — data/logs/{session}.jsonl + {session}_summary.json
## P8: 结构化世界事件 + 快照 + 异常标记；离线 digest 见 tools/digest_session.py
##

var _session_id: String = ""
var _log_path: String = ""
var _summary_path: String = ""
var _started_at: String = ""
var _summary_written: bool = false

var _stats: Dictionary = {
	"llm_calls": 0,
	"llm_errors": 0,
	"decisions": 0,
	"decision_errors": 0,
	"tokens_prompt": 0,
	"tokens_completion": 0,
	"tokens_total": 0,
	"by_request_type": {},
	"by_agent": {},
	"by_action_kind": {},
	"world_events": 0,
	"says": 0,
	"item_actions": 0,
	"snapshots": 0,
}

var _anomalies: Array = []
var _stuck_tracker: Dictionary = {}  # agent_id -> {tile_key, count}
var _last_say: Dictionary = {}  # agent_id -> {text, tick}


func _ready() -> void:
	_begin_session()


func _begin_session() -> void:
	_summary_written = false
	_session_id = Time.get_datetime_string_from_system().replace(":", "-")
	_started_at = Time.get_datetime_string_from_system()
	var log_dir := Config.repo_root().path_join("data/logs")
	DirAccess.make_dir_recursive_absolute(log_dir)
	_log_path = log_dir.path_join("%s.jsonl" % _session_id)
	_summary_path = log_dir.path_join("%s_summary.json" % _session_id)
	_stats = {
		"llm_calls": 0,
		"llm_errors": 0,
		"decisions": 0,
		"decision_errors": 0,
		"tokens_prompt": 0,
		"tokens_completion": 0,
		"tokens_total": 0,
		"by_request_type": {},
		"by_agent": {},
		"by_action_kind": {},
		"world_events": 0,
		"says": 0,
		"item_actions": 0,
		"snapshots": 0,
	}
	_anomalies.clear()
	_stuck_tracker.clear()
	_last_say.clear()
	log_event("session_start", {"session_id": _session_id})


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		write_session_summary()


func session_path() -> String:
	return _log_path


func summary_path() -> String:
	return _summary_path


func stats() -> Dictionary:
	return _stats.duplicate(true)


func anomalies() -> Array:
	return _anomalies.duplicate(true)


func log_event(event: String, fields: Dictionary = {}) -> void:
	var entry := {"event": event, "ts": Time.get_datetime_string_from_system()}
	for k in fields:
		entry[k] = fields[k]
	_write_line(entry)


func log_llm_response(meta: Dictionary, body: Dictionary, ok: bool, error: String = "") -> void:
	var usage: Dictionary = body.get("usage", {})
	var prompt_t: int = int(usage.get("prompt_tokens", 0))
	var completion_t: int = int(usage.get("completion_tokens", 0))
	var total_t: int = int(usage.get("total_tokens", prompt_t + completion_t))
	var req_type: String = str(meta.get("request_type", "chat"))
	var agent_id: String = str(meta.get("agent_id", ""))

	_stats["llm_calls"] += 1
	_stats["tokens_prompt"] += prompt_t
	_stats["tokens_completion"] += completion_t
	_stats["tokens_total"] += total_t
	_bump_nested(_stats, "by_request_type", req_type, 1)
	if not agent_id.is_empty():
		_bump_agent(agent_id, "llm_calls", 1)
		_bump_agent(agent_id, "tokens_total", total_t)
	if not ok:
		_stats["llm_errors"] += 1
		_record_anomaly(
			"llm_error",
			int(meta.get("tick", -1)),
			agent_id,
			"%s: %s" % [req_type, error],
		)

	log_event("llm_call", {
		"request_type": req_type,
		"agent_id": agent_id,
		"tick": meta.get("tick", -1),
		"model": str(body.get("model", Config.llm.get("model", ""))),
		"ok": ok,
		"error": error,
		"prompt_tokens": prompt_t,
		"completion_tokens": completion_t,
		"total_tokens": total_t,
	})


func log_decision(entry: Dictionary) -> void:
	_stats["decisions"] += 1
	var agent_id: String = str(entry.get("agent_id", ""))
	var ok: bool = str(entry.get("result", "")) == "ok"
	var tick: int = int(entry.get("tick", -1))
	if not ok:
		_stats["decision_errors"] += 1
		_record_anomaly(
			"decision_error",
			tick,
			agent_id,
			str(entry.get("error", "")),
		)
	var blocked: Array = entry.get("guard_blocked", [])
	if blocked.size() > 0:
		_record_anomaly(
			"guard_blocked",
			tick,
			agent_id,
			"patterns=%s" % str(blocked),
		)
	var action: Dictionary = entry.get("parsed_action", {})
	var kind: String = str(action.get("kind", ""))
	if not kind.is_empty():
		_bump_nested(_stats, "by_action_kind", kind, 1)
	if not agent_id.is_empty():
		_bump_agent(agent_id, "decisions", 1)
		if not kind.is_empty():
			_bump_agent_nested(agent_id, "actions", kind, 1)

	var row := entry.duplicate(true)
	row["event"] = "decision"
	row["ts"] = Time.get_datetime_string_from_system()
	_write_line(row)


func log_say(
	speaker_id: String,
	target_id: String,
	text: String,
	tick: int,
	recipient_ids: Array,
	ok: bool,
	error: String = "",
	tone: String = "neutral",
) -> void:
	_stats["says"] += 1
	log_event("say", {
		"tick": tick,
		"speaker": speaker_id,
		"target": target_id,
		"text": text,
		"tone": tone,
		"recipients": recipient_ids,
		"ok": ok,
		"error": error,
	})
	if not ok:
		_record_anomaly("say_failed", tick, speaker_id, error)
	else:
		_check_repeat_say(speaker_id, text, tick)


func log_action_result(
	agent_id: String,
	tick: int,
	kind: String,
	params: Dictionary,
	ok: bool,
	detail: String,
	error: String = "",
) -> void:
	var item_kinds: Array = ["PICK_UP", "DROP", "USE", "GIVE"]
	if kind in item_kinds:
		_stats["item_actions"] += 1
	log_event("action_result", {
		"tick": tick,
		"agent_id": agent_id,
		"kind": kind,
		"params": params,
		"ok": ok,
		"detail": detail,
		"error": error,
	})
	if not ok:
		_record_anomaly("action_failed", tick, agent_id, "%s: %s" % [kind, error if not error.is_empty() else detail])


func log_movement_stuck(agent_id: String, tick: int, tile: Vector2i) -> void:
	_record_anomaly(
		"movement_stuck",
		tick,
		agent_id,
		"walking abort at (%d, %d)" % [tile.x, tile.y],
	)


func log_reflection(agent_id: String, tick: int, text: String) -> void:
	log_event("reflection", {
		"tick": tick,
		"agent_id": agent_id,
		"text": text,
	})


func log_plan(agent_id: String, tick: int, text: String, steps: Array) -> void:
	log_event("plan", {
		"tick": tick,
		"agent_id": agent_id,
		"text": text,
		"steps": steps,
	})


func log_world_snapshot(tick: int, agents: Array) -> void:
	_stats["snapshots"] += 1
	log_event("world_snapshot", {
		"tick": tick,
		"agents": agents,
	})
	_track_stuck_agents(tick, agents)


func log_world_event_logged(event_id: String, text: String, tick: int) -> void:
	_stats["world_events"] += 1
	log_event("world_event", {"event_id": event_id, "text": text, "tick": tick})


func rotate_session(reason: String = "rotate") -> void:
	if not _summary_written:
		write_session_summary({"exit": reason})
	_begin_session()


func write_session_summary(extra: Dictionary = {}) -> void:
	if _summary_path.is_empty() or _summary_written:
		return
	_summary_written = true
	var digest_base := _log_path.replace(".jsonl", "")
	var summary := {
		"session_id": _session_id,
		"started_at": _started_at,
		"ended_at": Time.get_datetime_string_from_system(),
		"log_path": _log_path,
		"digest_md_path": "%s_digest.md" % digest_base,
		"digest_json_path": "%s_digest.json" % digest_base,
		"digest_tool": "python tools/digest_session.py",
		"stats": _stats.duplicate(true),
		"anomalies": _anomalies.duplicate(true),
	}
	for k in extra:
		summary[k] = extra[k]
	var file := FileAccess.open(_summary_path, FileAccess.WRITE)
	if file == null:
		push_warning("[Logger] cannot write summary %s" % _summary_path)
		return
	file.store_string(JSON.stringify(summary, "\t"))
	file.close()
	log_event("session_end", {"summary_path": _summary_path})


func _record_anomaly(kind: String, tick: int, agent_id: String, detail: String) -> void:
	var row := {
		"kind": kind,
		"tick": tick,
		"agent_id": agent_id,
		"detail": detail,
		"ts": Time.get_datetime_string_from_system(),
	}
	_anomalies.append(row)
	log_event("anomaly", row)


func _check_repeat_say(agent_id: String, text: String, tick: int) -> void:
	var window: int = int(Config.observability_cfg().get("repeat_say_window_ticks", 40))
	var prev: Dictionary = _last_say.get(agent_id, {})
	if prev.is_empty():
		_last_say[agent_id] = {"text": text, "tick": tick}
		return
	if str(prev.get("text", "")) == text and tick - int(prev.get("tick", 0)) <= window:
		_record_anomaly(
			"repeat_say",
			tick,
			agent_id,
			"repeated within %d ticks: %s" % [window, text.substr(0, 80)],
		)
	_last_say[agent_id] = {"text": text, "tick": tick}


func _track_stuck_agents(tick: int, agents: Array) -> void:
	var threshold: int = int(Config.observability_cfg().get("stuck_tile_threshold", 3))
	for row in agents:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var aid: String = str(row.get("id", ""))
		var tile_arr: Array = row.get("tile", [])
		if aid.is_empty() or tile_arr.size() < 2:
			continue
		var key := "%d,%d" % [int(tile_arr[0]), int(tile_arr[1])]
		var state: String = str(row.get("state", ""))
		var prev: Dictionary = _stuck_tracker.get(aid, {})
		if str(prev.get("tile_key", "")) == key:
			var count: int = int(prev.get("count", 0)) + 1
			_stuck_tracker[aid] = {"tile_key": key, "count": count, "state": state}
			if count == threshold:
				var kind := "stuck_idle" if state == "idle" else "stuck_walking"
				_record_anomaly(
					kind,
					tick,
					aid,
					"%s at (%s) for %d snapshots" % [state, key, count],
				)
		else:
			_stuck_tracker[aid] = {"tile_key": key, "count": 1, "state": state}


func _write_line(entry: Dictionary) -> void:
	if _log_path.is_empty():
		return
	var file := FileAccess.open(_log_path, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(_log_path, FileAccess.WRITE)
	if file == null:
		push_warning("[Logger] cannot open %s" % _log_path)
		return
	file.seek_end()
	file.store_line(JSON.stringify(entry))
	file.close()


func _bump_nested(root: Dictionary, key: String, subkey: String, delta: int) -> void:
	if not root.has(key):
		root[key] = {}
	var bucket: Dictionary = root[key]
	bucket[subkey] = int(bucket.get(subkey, 0)) + delta


func _bump_agent(agent_id: String, field: String, delta: int) -> void:
	if not _stats["by_agent"].has(agent_id):
		_stats["by_agent"][agent_id] = {
			"llm_calls": 0,
			"decisions": 0,
			"tokens_total": 0,
			"actions": {},
		}
	_stats["by_agent"][agent_id][field] = int(_stats["by_agent"][agent_id].get(field, 0)) + delta


func _bump_agent_nested(agent_id: String, field: String, subkey: String, delta: int) -> void:
	if not _stats["by_agent"].has(agent_id):
		_bump_agent(agent_id, "llm_calls", 0)
	var bucket: Dictionary = _stats["by_agent"][agent_id].get(field, {})
	bucket[subkey] = int(bucket.get(subkey, 0)) + delta
	_stats["by_agent"][agent_id][field] = bucket
