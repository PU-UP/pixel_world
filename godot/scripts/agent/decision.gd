extends Node
class_name AgentDecision
##
## Tick 驱动 LLM 决策 → executor → player + 记忆流写入/检索
##

signal decision_made(tick: int, raw_text: String, action: Dictionary, result: Dictionary)

const ActionExecutor = preload("res://scripts/agent/executor.gd")
const DecisionPrompt = preload("res://scripts/llm/prompts/decision.gd")
const LlmGuard = preload("res://scripts/llm/guard.gd")
const LlmParser = preload("res://scripts/llm/parser.gd")
const LlmClientScript = preload("res://scripts/llm/client.gd")
const LoggerScript = preload("res://scripts/observability/logger.gd")
const PersonaScript = preload("res://scripts/agent/persona.gd")
const MemoryStreamScript = preload("res://scripts/agent/memory/stream.gd")

var _player: Player = null
var _clock: GameClock = null
var _llm: LlmClientScript = null
var _logger: LoggerScript = null
var _persona: PersonaScript = null
var _memory: MemoryStreamScript = null

var _busy: bool = false
var _last_raw: String = ""
var _last_action: Dictionary = {}
var _last_error: String = ""
var enabled: bool = false


func setup(
	player: Player,
	clock: GameClock,
	llm: LlmClientScript,
	logger: LoggerScript,
	persona: PersonaScript,
	memory: MemoryStreamScript,
) -> void:
	_player = player
	_clock = clock
	_llm = llm
	_logger = logger
	_persona = persona
	_memory = memory
	_llm.completed.connect(_on_llm_completed)
	_llm.failed.connect(_on_llm_failed)
	if not _clock.tick.is_connected(_on_tick):
		_clock.tick.connect(_on_tick)


func set_enabled(on: bool) -> void:
	enabled = on


func get_last_decision_text() -> String:
	if not _last_error.is_empty():
		return "ERROR: %s" % _last_error
	if _last_action.is_empty():
		return _last_raw if not _last_raw.is_empty() else "(waiting)"
	return "%s\n→ %s" % [_last_raw, _format_action(_last_action)]


func _on_tick(_tick_index: int) -> void:
	if not enabled:
		return
	if _clock.paused:
		return
	if _busy:
		return
	if _player == null:
		return
	if Config.decision_skip_while_walking() and _player.is_busy():
		return
	if not _llm.is_configured():
		_last_error = "LLM API key not configured"
		return
	_request_decision()


func _request_decision() -> void:
	var tick := _clock.current_tick()
	var obs := _player.get_observation()
	var guard: Dictionary = LlmGuard.sanitize_observation(obs)
	_memory.append_event("observation", guard["text"], tick)
	var retrieved := _memory.retrieve_for_query(guard["text"], tick)
	var memory_lines := _format_memories(retrieved)
	var messages: Array = DecisionPrompt.build_messages(
		_persona.describe(),
		guard["text"],
		_player.get_status_line(),
		_player.get_action_log_lines(4),
		memory_lines,
	)
	_busy = true
	_last_error = ""
	var meta := {
		"request_type": "decision",
		"tick": tick,
		"agent_id": str(_player.agent_id),
		"observation": guard["text"],
		"guard_blocked": guard["blocked"],
	}
	_llm.request_decision(messages, meta)


func _on_llm_completed(_request_id: int, body: Dictionary, meta: Dictionary) -> void:
	if str(meta.get("request_type", "")) != "decision":
		return
	_busy = false
	var parsed: Dictionary = LlmParser.parse_response(body)
	_last_raw = parsed.get("raw_text", "")
	var result: Dictionary
	var tick := int(meta.get("tick", -1))
	if parsed["ok"]:
		_last_action = parsed["action"]
		_last_error = ""
		result = ActionExecutor.execute(_player, _last_action)
		_memory.append_event(
			"decision",
			"chose %s" % _format_action(_last_action),
			tick,
			0.1,
			0.0,
			0.3,
		)
		if result.get("ok", false):
			_memory.append_event(
				"action",
				"executed %s" % _format_action(_last_action),
				tick,
				0.0,
				0.0,
				0.4,
			)
	else:
		_last_action = {}
		_last_error = parsed["error"]
		result = {"ok": false, "error": parsed["error"]}
	decision_made.emit(tick, _last_raw, _last_action, result)
	_log(meta, _last_raw, _last_action, result)


func _on_llm_failed(_request_id: int, error: String, meta: Dictionary) -> void:
	if str(meta.get("request_type", "")) != "decision":
		return
	_busy = false
	_last_error = error
	_last_action = {}
	var result := {"ok": false, "error": error}
	decision_made.emit(int(meta.get("tick", -1)), "", {}, result)
	_log(meta, "", {}, result)


func _log(meta: Dictionary, raw_text: String, action: Dictionary, result: Dictionary) -> void:
	if _logger == null:
		return
	_logger.log_decision({
		"tick": meta.get("tick", -1),
		"agent_id": meta.get("agent_id", ""),
		"observation": meta.get("observation", ""),
		"guard_blocked": meta.get("guard_blocked", []),
		"raw_output": raw_text,
		"parsed_action": action,
		"result": "ok" if result.get("ok", false) else "error",
		"error": str(result.get("error", "")),
	})


func _format_action(action: Dictionary) -> String:
	if action.is_empty():
		return "(none)"
	return "[%s] %s" % [action.get("kind", "?"), str(action.get("params", {}))]


func _format_memories(memories: Array) -> PackedStringArray:
	var lines: PackedStringArray = []
	for mem in memories:
		lines.append(
			"[t%d|%s|imp=%.2f] %s" % [
				int(mem.get("tick", -1)),
				str(mem.get("category", "?")),
				float(mem.get("importance", 0.0)),
				str(mem.get("text", "")).substr(0, 100),
			]
		)
	return lines
