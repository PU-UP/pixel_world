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
const AgentGoals = preload("res://scripts/agent/goals.gd")

var _player: Player = null
var _clock: GameClock = null
var _llm: LlmClientScript = null
var _persona: PersonaScript = null
var _memory: MemoryStreamScript = null
var _comm: CommRouterScript = null
var _relationships: AgentRelationships = null
var _goals: AgentGoals = null
var _agent_id: String = ""

var _steps: Array = []
var _step_index: int = 0
var _ticks_since_plan: int = 0
var _busy: bool = false
var _last_plan_text: String = ""
var enabled: bool = true
var _logger = null


func setup(
	player: Player,
	clock: GameClock,
	llm: LlmClientScript,
	persona: PersonaScript,
	memory: MemoryStreamScript,
	comm: CommRouterScript,
	relationships: AgentRelationships,
	goals: AgentGoals = null,
) -> void:
	_player = player
	_clock = clock
	_llm = llm
	_persona = persona
	_memory = memory
	_comm = comm
	_relationships = relationships
	_goals = goals
	_agent_id = str(player.agent_id)
	_llm.completed.connect(_on_llm_completed)
	_llm.failed.connect(_on_llm_failed)
	if not _clock.tick.is_connected(_on_tick):
		_clock.tick.connect(_on_tick)


func set_logger(logger) -> void:
	_logger = logger


func get_remaining_steps() -> PackedStringArray:
	var lines: PackedStringArray = []
	for i in range(_step_index, _steps.size()):
		lines.append("%d. %s" % [i + 1, str(_steps[i])])
	return lines


func get_last_plan_text() -> String:
	if _last_plan_text.is_empty():
		return "(no plan yet)"
	return _last_plan_text


func capture_save() -> Dictionary:
	var steps: Array = []
	for s in _steps:
		steps.append(str(s))
	return {
		"steps": steps,
		"step_index": _step_index,
		"ticks_since_plan": _ticks_since_plan,
		"last_plan_text": _last_plan_text,
	}


func restore_save(data: Dictionary) -> void:
	_steps.clear()
	for s in data.get("steps", []):
		_steps.append(str(s))
	_step_index = clampi(int(data.get("step_index", 0)), 0, _steps.size())
	_ticks_since_plan = maxi(0, int(data.get("ticks_since_plan", 0)))
	_last_plan_text = str(data.get("last_plan_text", ""))
	_busy = false


func advance_step() -> void:
	if _step_index < _steps.size():
		_step_index += 1


func step_matches(action: Dictionary) -> bool:
	if action.is_empty() or _steps.is_empty() or _step_index >= _steps.size():
		return false
	var step: String = str(_steps[_step_index]).strip_edges().to_lower()
	if step.is_empty():
		return false
	var kind: String = str(action.get("kind", "")).strip_edges().to_upper()
	if kind.is_empty():
		return false
	var step_compact: String = step.replace(" ", "")
	if step.find(kind.to_lower()) >= 0:
		if kind == "MOVE_TO":
			return _move_matches_step(action, step_compact)
		return true
	match kind:
		"MOVE_TO":
			return _move_matches_step(action, step_compact)
		"SAY":
			return _contains_any(step, ["说", "交谈", "招呼", "对话", "回答"])
		"PICK_UP":
			return _contains_any(step, ["捡", "拾", "采集", "收"])
		"USE":
			return _contains_any(step, ["吃", "用", "喂"])
		"GIVE":
			return _contains_any(step, ["给", "递", "送"])
		"SLEEP":
			return _contains_any(step, ["睡", "休息"])
		"SHARE_MAP":
			return _contains_any(step, ["地图", "share"])
		"OBSERVE":
			return _contains_any(step, ["观察", "看"])
		"WAIT":
			return _contains_any(step, ["等", "wait"])
		"EMOTE":
			return _contains_any(step, ["表情", "emote"])
		_:
			return false


func advance_if_matches(action: Dictionary) -> bool:
	if not step_matches(action):
		return false
	advance_step()
	return true


func _on_tick(_tick_index: int) -> void:
	if not enabled or _clock.paused or _busy:
		return
	_ticks_since_plan += 1
	if _player != null and _player.is_dead():
		return
	if _player != null and (_player.is_sleeping() or _player.is_waiting() or _player.is_walking()):
		return
	var trigger: int = int(Config.planning_cfg().get("trigger_ticks", 50))
	if _steps.is_empty() or _step_index >= _steps.size() or _ticks_since_plan >= trigger:
		_request_plan()


func _request_plan() -> void:
	if not _llm.is_configured() or _player == null:
		return
	var tick := _clock.current_tick()
	var nearby := _nearby_ids()
	var rel_lines := _relationships.format_for_decision(nearby) if _relationships else PackedStringArray()
	var goal_text := _goals.format_for_prompt() if _goals != null else ""
	var frontier_lines: PackedStringArray = PackedStringArray()
	if _player != null:
		for ft in _player.cached_frontier_tiles():
			var tile: Vector2i = ft
			frontier_lines.append("(%d,%d)" % [tile.x, tile.y])
	var messages: Array = PlanningPrompt.build_messages(
		_persona.describe(),
		_player.get_status_line(),
		_player.get_observation(),
		_player.get_action_log_lines(4),
		rel_lines,
		goal_text,
		frontier_lines,
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
	_sync_current_goal()
	var tick := int(meta.get("tick", _clock.current_tick()))
	_memory.append_event("plan", text, tick, 0.2, 0.1, 0.5)
	if _logger != null:
		_logger.log_plan(_agent_id, tick, text, _steps)
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


func _sync_current_goal() -> void:
	if _goals == null:
		return
	var headline: String = ""
	if _step_index < _steps.size():
		headline = str(_steps[_step_index]).strip_edges()
	elif not _steps.is_empty():
		headline = str(_steps[0]).strip_edges()
	if headline.is_empty():
		return
	if headline.length() > 40:
		headline = headline.substr(0, 40)
	_goals.set_current(headline)


func _move_matches_step(action: Dictionary, step_compact: String) -> bool:
	var params: Dictionary = action.get("params", {})
	var x: int = int(params.get("x", 0))
	var y: int = int(params.get("y", 0))
	var coord: String = "(%d,%d)" % [x, y]
	var coord_alt: String = "%d,%d" % [x, y]
	if step_compact.find(coord) >= 0 or step_compact.find(coord_alt) >= 0:
		return true
	if step_compact.find("(") >= 0 and step_compact.find(",") >= 0:
		return false
	return _contains_any(step_compact, ["前往", "探索", "边界", "果园", "南滩", "北脊", "西林", "东岸", "草甸"])


func _contains_any(text: String, tokens: Array) -> bool:
	for token in tokens:
		if text.find(str(token)) >= 0:
			return true
	return false
