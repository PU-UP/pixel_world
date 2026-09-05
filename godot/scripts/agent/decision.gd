extends Node
class_name AgentDecision
##
## Tick 驱动 LLM 决策 → gate → executor → 记忆流
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
const CommRouterScript = preload("res://scripts/agent/comm.gd")
const AgentPlanning = preload("res://scripts/agent/planning.gd")
const AgentRelationships = preload("res://scripts/agent/relationships.gd")
const AgentGoals = preload("res://scripts/agent/goals.gd")
const AgentActions = preload("res://scripts/agent/actions.gd")

var _player: Player = null
var _clock: GameClock = null
var _llm: LlmClientScript = null
var _logger: LoggerScript = null
var _persona: PersonaScript = null
var _memory: MemoryStreamScript = null
var _comm: CommRouterScript = null
var _planning: AgentPlanning = null
var _relationships: AgentRelationships = null
var _goals: AgentGoals = null

var _busy: bool = false
var _last_raw: String = ""
var _last_action: Dictionary = {}
var _last_error: String = ""
var _last_decision_tick: int = -999
var _bad_move_keys: Array = []
var enabled: bool = false


func setup(
	player: Player,
	clock: GameClock,
	llm: LlmClientScript,
	logger: LoggerScript,
	persona: PersonaScript,
	memory: MemoryStreamScript,
	comm: CommRouterScript = null,
	planning: AgentPlanning = null,
	relationships: AgentRelationships = null,
	goals: AgentGoals = null,
) -> void:
	_player = player
	_clock = clock
	_llm = llm
	_logger = logger
	_persona = persona
	_memory = memory
	_comm = comm
	_planning = planning
	_relationships = relationships
	_goals = goals
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
	if _player.is_dead():
		return
	if _player.is_sleeping() or _player.is_waiting():
		return
	if Config.decision_skip_while_walking() and _player.is_walking():
		return
	var min_gap: int = Config.decision_min_ticks_between()
	if min_gap > 0 and _clock.current_tick() - _last_decision_tick < min_gap:
		return
	if not _llm.is_configured():
		_last_error = "LLM API key not configured"
		return
	_request_decision()


func _request_decision() -> void:
	var tick := _clock.current_tick()
	var obs := _player.get_observation_for_llm()
	var guard: Dictionary = LlmGuard.sanitize_observation(obs)
	var retrieved := _memory.retrieve_for_query(guard["text"], tick)
	var memory_lines := _format_memories(retrieved)
	var perception_ids := _perception_agent_ids()
	var ground_ids := _ground_item_ids()
	var heard_lines := _player.get_recent_heard_lines(4)
	var plan_lines := _planning.get_remaining_steps() if _planning else PackedStringArray()
	var rel_lines := _relationships.format_for_decision(perception_ids) if _relationships else PackedStringArray()
	var item_lines := _player.get_nearby_item_lines()
	var world = _player.game_world()
	var walkable_near := AgentActions.nearby_walkable_tiles(
		world,
		_player.get_tile_position(),
		Config.exploration_local_move_radius(),
	)
	var frontier_lines: PackedStringArray = PackedStringArray()
	for ft in _player.cached_frontier_tiles():
		var tile: Vector2i = ft
		frontier_lines.append("(%d,%d)" % [tile.x, tile.y])
	var ctx: Dictionary = AgentActions.build_context(_player, _comm, world)
	var social_ids := _audio_agent_ids()
	var tools: Array = DecisionPrompt.tool_definitions_for_context(
		social_ids,
		_perception_agent_ids(),
		_ground_item_ids(),
		_packed_strings(ctx.get("pickup_item_ids", [])),
		ctx.get("inventory", []),
	)
	var goal_lines := _goal_lines()
	var pending := _player.get_pending_reply_line()
	var pending_from := _player.get_pending_reply_from()
	if not pending.is_empty() and not _id_in_packed(social_ids, pending_from):
		pending = ""
	var messages: Array = DecisionPrompt.build_messages(
		_persona.describe(),
		guard["text"],
		_player.get_status_line(),
		memory_lines,
		perception_ids,
		social_ids,
		perception_ids,
		ground_ids,
		heard_lines,
		plan_lines,
		rel_lines,
		item_lines,
		pending,
		_player.get_last_say_text(),
		walkable_near,
		_bad_move_lines(),
		goal_lines,
		frontier_lines,
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
	_last_decision_tick = tick
	_llm.request_decision(messages, meta, tools)


func _on_llm_completed(_request_id: int, body: Dictionary, meta: Dictionary) -> void:
	if str(meta.get("request_type", "")) != "decision":
		return
	if str(meta.get("agent_id", "")) != str(_player.agent_id):
		return
	_busy = false
	var parsed: Dictionary = LlmParser.parse_response(body)
	_last_raw = parsed.get("raw_text", "")
	var tick := int(meta.get("tick", -1))
	var result: Dictionary
	if parsed["ok"]:
		var action: Dictionary = _normalize_action(parsed["action"])
		var gate: Dictionary = _gate_action(action)
		if not gate["ok"]:
			action = _maybe_redirect_action(action, gate)
			gate = _gate_action(action)
		if gate["ok"] and action["kind"] == AgentActions.KIND_SAY:
			var say_text: String = str(action["params"].get("text", "")).strip_edges()
			if _say_too_long(say_text):
				result = {"ok": false, "error": "say_too_long"}
				_last_action = action
				_last_error = result["error"]
			elif _player.would_repeat_say(say_text):
				result = {"ok": false, "error": "repeat_say_blocked"}
				_last_action = action
				_last_error = result["error"]
			else:
				_last_action = action
				_last_error = ""
				result = ActionExecutor.execute(_player, action, _comm, _clock)
		elif gate["ok"]:
			_last_action = action
			_last_error = ""
			result = ActionExecutor.execute(_player, action, _comm, _clock)
		elif not gate["ok"] and str(gate.get("hint", "")) == "already_there":
			_last_action = action
			_last_error = ""
			result = {"ok": true, "error": "", "detail": "skipped duplicate move"}
		else:
			_last_action = action
			_last_error = gate["error"]
			result = {"ok": false, "error": gate["error"]}
			if action.get("kind", "") == AgentActions.KIND_MOVE_TO:
				var fail_goal := Vector2i(
					int(action["params"].get("x", 0)),
					int(action["params"].get("y", 0)),
				)
				_mark_bad_move_tile(fail_goal)
		_record_outcome(tick, action, result)
		if result.get("ok", false) and _planning:
			_planning.advance_step()
	else:
		_last_action = {}
		_last_error = parsed["error"]
		result = {"ok": false, "error": parsed["error"]}
	decision_made.emit(tick, _last_raw, _last_action, result)
	_log(meta, _last_raw, _last_action, result)


func _on_llm_failed(_request_id: int, error: String, meta: Dictionary) -> void:
	if str(meta.get("request_type", "")) != "decision":
		return
	if str(meta.get("agent_id", "")) != str(_player.agent_id):
		return
	_busy = false
	_last_error = error
	_last_action = {}
	var result := {"ok": false, "error": error}
	decision_made.emit(int(meta.get("tick", -1)), "", {}, result)
	_log(meta, "", {}, result)


func _normalize_action(action: Dictionary) -> Dictionary:
	var out := action.duplicate(true)
	var kind: String = str(out.get("kind", ""))
	var params: Dictionary = out.get("params", {})
	if kind == AgentActions.KIND_SAY or kind == AgentActions.KIND_GIVE:
		if _comm != null and params.has("to"):
			params["to"] = _comm.resolve_agent_id(str(params.get("to", "")))
	if kind == AgentActions.KIND_OBSERVE and params.has("target"):
		params["target"] = str(params.get("target", "")).strip_edges()
		if _comm != null:
			var resolved_obs: String = _comm.resolve_agent_id(str(params["target"]))
			if _comm.find_player(resolved_obs) != null:
				params["target"] = resolved_obs
	if kind == AgentActions.KIND_MOVE_TO:
		var world = _player.game_world()
		var start: Vector2i = _player.get_tile_position()
		var goal := Vector2i(int(params.get("x", 0)), int(params.get("y", 0)))
		var resolved: Dictionary = AgentActions.resolve_move_goal(world, start, goal)
		if resolved.get("ok", false):
			var tile: Vector2i = resolved.get("tile", goal)
			params["x"] = tile.x
			params["y"] = tile.y
		else:
			_mark_bad_move_tile(goal)
	out["params"] = params
	return out


func _gate_action(action: Dictionary) -> Dictionary:
	var ctx: Dictionary = AgentActions.build_context(_player, _comm, _player.game_world())
	ctx["blocked_move_tiles"] = _bad_move_keys.duplicate()
	return AgentActions.validate_in_context(action, ctx)


func _maybe_redirect_action(action: Dictionary, gate: Dictionary) -> Dictionary:
	var hint: String = str(gate.get("hint", ""))
	if hint == "snap_move":
		var snap: Variant = gate.get("snap_tile", null)
		if snap is Vector2i:
			return AgentActions.make_move_to(snap.x, snap.y)
		return action
	if hint == "approach_agent":
		var approach_id: String = str(gate.get("approach_id", "")).strip_edges()
		if _comm != null and not approach_id.is_empty():
			var other: Player = _comm.find_player(approach_id)
			if other != null:
				return _redirect_to_meeting(other)
		return action
	if hint != "move_closer":
		return action
	var kind: String = str(action.get("kind", ""))
	if kind != AgentActions.KIND_SAY and kind != AgentActions.KIND_GIVE and kind != AgentActions.KIND_SHARE_MAP:
		return action
	var target_id: String = str(action["params"].get("to", "")).strip_edges()
	if kind == AgentActions.KIND_SAY and not _player.get_pending_reply_from().is_empty():
		target_id = _player.get_pending_reply_from()
	if target_id.is_empty() or target_id == "broadcast" or _comm == null:
		return action
	var other: Player = _comm.find_player(target_id)
	if other == null:
		return action
	return _redirect_to_meeting(other)


func _redirect_to_meeting(other: Player) -> Dictionary:
	var ctx: Dictionary = AgentActions.build_context(_player, _comm, _player.game_world())
	var meet: Dictionary = AgentActions.resolve_meeting_tile(
		_player.game_world(),
		_player.get_tile_position(),
		other.get_tile_position(),
		ctx.get("occupied_tiles", []),
	)
	if meet.get("ok", false):
		var tile: Vector2i = meet.get("tile", _player.get_tile_position())
		return AgentActions.make_move_to(tile.x, tile.y)
	var fallback: Vector2i = other.get_tile_position()
	return AgentActions.make_move_to(fallback.x, fallback.y)


func _record_outcome(tick: int, action: Dictionary, result: Dictionary) -> void:
	if action.is_empty():
		return
	var line := _format_action(action)
	if result.get("ok", false):
		_memory.append_event("action", "ok %s" % line, tick, 0.0, 0.0, 0.35)
	else:
		_memory.append_event(
			"action_failed",
			"%s → %s" % [line, str(result.get("error", "?"))],
			tick,
			0.15,
			0.0,
			0.2,
		)


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


func _perception_agent_ids() -> PackedStringArray:
	var ids: PackedStringArray = []
	if _comm == null or _player == null:
		return ids
	for p in _comm.players_in_perception(_player):
		ids.append(str(p.agent_id))
	return ids


func _audio_agent_ids() -> PackedStringArray:
	var ids: PackedStringArray = []
	if _comm == null or _player == null:
		return ids
	for p in _comm.players_in_audio(_player):
		if p.is_dead():
			continue
		ids.append(str(p.agent_id))
	return ids


func _ground_item_ids() -> PackedStringArray:
	var ids: PackedStringArray = []
	if _player == null or _player.game_world() == null or _player.game_world().state == null:
		return ids
	for item in _player.game_world().state.items_in_sight(
		_player.get_tile_position(),
		_player.perception_radius(),
		_player.game_world(),
	):
		var iid: String = str(item.get("item_id", ""))
		if not iid.is_empty() and not iid in ids:
			ids.append(iid)
	return ids


func _id_in_packed(ids: PackedStringArray, id: String) -> bool:
	var key: String = id.strip_edges()
	if key.is_empty():
		return false
	for entry in ids:
		if str(entry).strip_edges() == key:
			return true
	return false


func _packed_strings(items: Array) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for item in items:
		var s: String = str(item).strip_edges()
		if not s.is_empty():
			out.append(s)
	return out


func _mark_bad_move_tile(tile: Vector2i) -> void:
	var key: String = "%d,%d" % [tile.x, tile.y]
	_bad_move_keys.erase(key)
	_bad_move_keys.insert(0, key)
	while _bad_move_keys.size() > 8:
		_bad_move_keys.pop_back()


func _bad_move_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	for key in _bad_move_keys:
		lines.append("(%s) unwalkable or unreachable" % key)
	return lines


func _goal_lines() -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	if _goals == null:
		return lines
	var text: String = _goals.format_for_prompt()
	if not text.is_empty():
		lines.append(text)
	return lines


func _say_too_long(text: String) -> bool:
	var max_chars: int = Config.decision_max_say_chars()
	return max_chars > 0 and text.length() > max_chars


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
