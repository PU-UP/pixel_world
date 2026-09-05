extends Node
class_name AgentReflection
##
## 周期反思 — 每 K 事件或 M tick 触发 LLM 反思, 写入记忆流
##

signal reflection_done(tick: int, text: String)

const ReflectionPrompt = preload("res://scripts/llm/prompts/reflection.gd")
const LlmClientScript = preload("res://scripts/llm/client.gd")
const MemoryStreamScript = preload("res://scripts/agent/memory/stream.gd")
const PersonaScript = preload("res://scripts/agent/persona.gd")

var _memory: MemoryStreamScript = null
var _clock: GameClock = null
var _llm: LlmClientScript = null
var _persona: PersonaScript = null
var _agent_id: String = ""
var _logger = null

var _busy: bool = false
var _last_reflection: String = ""
var _ticks_since_reflection: int = 0
var enabled: bool = true
var _player = null


func setup(
	memory: MemoryStreamScript,
	clock: GameClock,
	llm: LlmClientScript,
	persona: PersonaScript,
	agent_id: String = "",
	player = null,
) -> void:
	_memory = memory
	_clock = clock
	_llm = llm
	_persona = persona
	_agent_id = agent_id if not agent_id.is_empty() else str(persona.agent_id)
	_player = player
	_llm.completed.connect(_on_llm_completed)
	_llm.failed.connect(_on_llm_failed)
	if not _clock.tick.is_connected(_on_tick):
		_clock.tick.connect(_on_tick)
	if not _memory.memory_added.is_connected(_on_memory_added):
		_memory.memory_added.connect(_on_memory_added)


func set_logger(logger) -> void:
	_logger = logger


func get_last_reflection_text() -> String:
	return _last_reflection if not _last_reflection.is_empty() else _memory.latest_reflection_summary()


func _on_memory_added(mem: Dictionary) -> void:
	if str(mem.get("category", "")) == "reflection":
		return
	_maybe_trigger_reflection()


func _on_tick(_tick_index: int) -> void:
	if not enabled or _clock.paused:
		return
	if _player != null and _player.is_dead():
		return
	_ticks_since_reflection += 1
	_memory.maybe_decay(_clock.current_tick())
	var cfg := Config.memory_reflection_cfg()
	var trigger_ticks: int = int(cfg.get("trigger_ticks", 100))
	if _ticks_since_reflection >= trigger_ticks:
		_request_reflection()


func _maybe_trigger_reflection() -> void:
	var cfg := Config.memory_reflection_cfg()
	var trigger_events: int = int(cfg.get("trigger_events", 10))
	if _memory.event_count() >= trigger_events:
		_request_reflection()


func _request_reflection() -> void:
	if not enabled or _busy or not _llm.is_configured():
		return
	if _player != null and _player.is_dead():
		return
	var lookback: int = int(Config.memory_reflection_cfg().get("lookback", 50))
	var recent := _memory.get_recent(lookback)
	if recent.is_empty():
		return
	var messages: Array = ReflectionPrompt.build_messages(_persona.describe(), recent)
	_busy = true
	_llm.request_chat(messages, {
		"request_type": "reflection",
		"tick": _clock.current_tick(),
		"agent_id": str(_persona.agent_id),
	})


func _on_llm_completed(_request_id: int, body: Dictionary, meta: Dictionary) -> void:
	if str(meta.get("request_type", "")) != "reflection":
		return
	if str(meta.get("agent_id", "")) != _agent_id:
		return
	_busy = false
	var text := _extract_text(body)
	if text.is_empty():
		return
	_last_reflection = text
	_memory.append_event("reflection", text, int(meta.get("tick", _clock.current_tick())), 0.6, 0.0, 0.5)
	_memory.reset_event_count()
	_ticks_since_reflection = 0
	var social_n := _count_social_memories()
	_persona.apply_reflection_drift(social_n)
	if _logger != null:
		_logger.log_reflection(_agent_id, int(meta.get("tick", -1)), text)
	reflection_done.emit(int(meta.get("tick", -1)), text)


func _on_llm_failed(_request_id: int, _error: String, meta: Dictionary) -> void:
	if str(meta.get("request_type", "")) != "reflection":
		return
	if str(meta.get("agent_id", "")) != _agent_id:
		return
	_busy = false


func _extract_text(body: Dictionary) -> String:
	var choices: Array = body.get("choices", [])
	if choices.is_empty():
		return ""
	return str(choices[0].get("message", {}).get("content", "")).strip_edges()


func _count_social_memories() -> int:
	var recent := _memory.get_recent(20)
	var n := 0
	for mem in recent:
		var cat := str(mem.get("category", ""))
		if cat in ["action", "decision"]:
			var txt := str(mem.get("text", ""))
			if "SAY" in txt or "say" in txt or "heard" in txt:
				n += 1
	return n
