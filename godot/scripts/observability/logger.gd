extends Node
class_name ObservabilityLogger
##
## 维护向观测日志 — data/logs/{session}.jsonl + {session}_summary.json
## 记录 LLM 调用（含 token）、决策结果；退出时写 session 汇总
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
}


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
	}
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
	if not ok:
		_stats["decision_errors"] += 1
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


func rotate_session(reason: String = "rotate") -> void:
	if not _summary_written:
		write_session_summary({"exit": reason})
	_begin_session()


func write_session_summary(extra: Dictionary = {}) -> void:
	if _summary_path.is_empty() or _summary_written:
		return
	_summary_written = true
	var summary := {
		"session_id": _session_id,
		"started_at": _started_at,
		"ended_at": Time.get_datetime_string_from_system(),
		"log_path": _log_path,
		"stats": _stats.duplicate(true),
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
