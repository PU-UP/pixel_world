extends Node
class_name AgentPlanning
##
## 周期规划 — 每 M tick 生成计划, 注入决策 prompt
##

signal plan_updated(tick: int, steps: Array)

const PlanningPrompt = preload("res://scripts/llm/prompts/planning.gd")
const LlmClientScript = preload("res://scripts/llm/client.gd")
const MemoryStreamScript = preload("res://scripts/agent/memory/stream.gd")
const PersonaScript = preload("res://scripts/agent/persona.gd")
const CommRouterScript = preload("res://scripts/agent/comm.gd")
const AgentRelationships = preload("res://scripts/agent/relationships.gd")

var _player: Player = null
var _clock: GameClock = null
var _llm: LlmClientScript = null
var _persona: PersonaScript = null
var _memory: MemoryStreamScript = null
var _comm: CommRouterScript = null
var _relationships: AgentRelationships = null
var _agent_id: String = ""

var _steps: Array = []
var _step_index: int = 0
var _ticks_since_plan: int = 0
var _busy: bool = false
var _last_plan_text: String = ""
var enabled: bool = true


func setup(
	player: Player,
	clock: GameClock,
	llm: LlmClientScript,
	persona: PersonaScript,
	memory: MemoryStreamScript,
	comm: CommRouterScript,
	relationships: AgentRelationships,
) -> void:
	_player = player
	_clock = clock
	_llm = llm
	_persona = persona
	_memory = memory
	_comm = comm
	_relationships = relationships
	_agent_id = str(player.agent_id)
	_llm.completed.connect(_on_llm_completed)
	_llm.failed.connect(_on_llm_failed)
	if not _clock.tick.is_connected(_on_tick):
		_clock.tick.connect(_on_tick)


func get_remaining_steps() -> PackedStringArray:
	var lines: PackedStringArray = []
	for i in range(_step_index, _steps.size()):
		lines.append("%d. %s" % [i + 1, str(_steps[i])])
	return lines


func get_last_plan_text() -> String:
	if _last_plan_text.is_empty():
		return "(no plan yet)"
	return _last_plan_text


func advance_step() -> void:
	if _step_index < _steps.size():
		_step_index += 1


func _on_tick(_tick_index: int) -> void:
	if not enabled or _clock.paused or _busy:
		return
	_ticks_since_plan += 1
	var trigger: int = int(Config.planning_cfg().get("trigger_ticks", 50))
	if _steps.is_empty() or _step_index >= _steps.size() or _ticks_since_plan >= trigger:
		_request_plan()


func _request_plan() -> void:
	if not _llm.is_configured() or _player == null:
		return
	var tick := _clock.current_tick()
	var nearby := _nearby_ids()
	var rel_lines := _relationships.format_for_decision(nearby) if _relationships else PackedStringArray()
	var messages: Array = PlanningPrompt.build_messages(
		_persona.describe(),
		_player.get_status_line(),
		_player.get_observation(),
		_player.get_action_log_lines(4),
		rel_lines,
	)
	_busy = true
	_llm.request_chat(messages, {
		"request_type": "planning",
		"tick": tick,
		"agent_id": _agent_id,
	})


func _on_llm_completed(_request_id: int, body: Dictionary, meta: Dictionary) -> void:
	if str(meta.get("request_type", "")) != "planning":
		return
	if str(meta.get("agent_id", "")) != _agent_id:
		return
	_busy = false
	var text := _extract_text(body)
	if text.is_empty():
		return
	_last_plan_text = text
	_steps = _parse_steps(text)
	_step_index = 0
	_ticks_since_plan = 0
	var tick := int(meta.get("tick", _clock.current_tick()))
	_memory.append_event("plan", text, tick, 0.2, 0.1, 0.5)
	plan_updated.emit(tick, _steps)


func _on_llm_failed(_request_id: int, _error: String, meta: Dictionary) -> void:
	if str(meta.get("request_type", "")) != "planning":
		return
	if str(meta.get("agent_id", "")) != _agent_id:
		return
	_busy = false


func _nearby_ids() -> PackedStringArray:
	var ids: PackedStringArray = []
	if _comm == null or _player == null:
		return ids
	for p in _comm.players_in_perception(_player):
		ids.append(str(p.agent_id))
	return ids


func _extract_text(body: Dictionary) -> String:
	var choices: Array = body.get("choices", [])
	if choices.is_empty():
		return ""
	return str(choices[0].get("message", {}).get("content", "")).strip_edges()


func _parse_steps(text: String) -> Array:
	var max_steps: int = int(Config.planning_cfg().get("max_steps", 7))
	var steps: Array = []
	for line in text.split("\n"):
		var s := line.strip_edges()
		if s.is_empty():
			continue
		if s[0].is_valid_int():
			var dot := s.find(".")
			if dot >= 0:
				s = s.substr(dot + 1).strip_edges()
		elif s.begins_with("- "):
			s = s.substr(2).strip_edges()
		if not s.is_empty():
			steps.append(s)
		if steps.size() >= max_steps:
			break
	return steps
