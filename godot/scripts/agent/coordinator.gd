extends Node
class_name AgentCoordinator
##
## 多 agent 生命周期 — 生成、运行时组件、选中
##

signal roster_changed()

const PlayerScript = preload("res://scripts/player.gd")
const PersonaScript = preload("res://scripts/agent/persona.gd")
const MemoryStreamScript = preload("res://scripts/agent/memory/stream.gd")
const DecisionScript = preload("res://scripts/agent/decision.gd")
const ReflectionScript = preload("res://scripts/agent/reflection.gd")
const PlanningScript = preload("res://scripts/agent/planning.gd")
const RelationshipsScript = preload("res://scripts/agent/relationships.gd")
const CommRouterScript = preload("res://scripts/agent/comm.gd")
const AgentGoalsScript = preload("res://scripts/agent/goals.gd")
const AgentScene = preload("res://scenes/entities/Agent.tscn")
const SessionResetScript = preload("res://scripts/session_reset.gd")
const SaveGameScript = preload("res://scripts/world/save_game.gd")

var records: Array = []
var comm: CommRouterScript = null
var selected_index: int = 0

var _world = null
var _clock = null
var _llm = null
var _logger = null
var _agents_root: Node2D = null
var _runtime_parent: Node = null


func setup(world, clock, llm, logger, agents_root: Node2D, runtime_parent: Node) -> void:
	_world = world
	_clock = clock
	_llm = llm
	_logger = logger
	_agents_root = agents_root
	_runtime_parent = runtime_parent
	comm = CommRouterScript.new()
	comm.name = "CommRouter"
	_runtime_parent.add_child(comm)
	comm.message_delivered.connect(_on_message_delivered)
	comm.item_given.connect(_on_item_given)
	if not _clock.tick.is_connected(_on_clock_tick):
		_clock.tick.connect(_on_clock_tick)
	_spawn_agents()


var _co_presence_counter: int = 0


func _on_clock_tick(tick: int) -> void:
	_co_presence_counter += 1
	if _co_presence_counter >= 10:
		_co_presence_counter = 0
		tick_co_presence()
	_maybe_log_snapshot(tick)


func spawn_count() -> int:
	return records.size()


func all_agent_ids() -> Array:
	var ids: Array = []
	for rec in records:
		ids.append(str(rec["player"].agent_id))
	return ids


func selected_record() -> Dictionary:
	if records.is_empty():
		return {}
	return records[selected_index % records.size()]


func select_index(i: int) -> void:
	if records.is_empty():
		return
	selected_index = i % records.size()
	_refresh_selection_highlight()
	roster_changed.emit()


func cycle_selection() -> void:
	select_index(selected_index + 1)


func set_agent_mode(enabled: bool) -> void:
	for rec in records:
		rec["decision"].set_enabled(enabled)


func reset_world(agent_mode: bool = false) -> void:
	_destroy_runtime()
	SessionResetScript.wipe_persisted_agent_data()
	_clock.reset()
	_world.reset_tile_overrides()
	_world.state.reset()
	_world.events.reset()
	_co_presence_counter = 0
	comm = CommRouterScript.new()
	comm.name = "CommRouter"
	_runtime_parent.add_child(comm)
	comm.message_delivered.connect(_on_message_delivered)
	comm.item_given.connect(_on_item_given)
	_spawn_agents()
	set_agent_mode(agent_mode)
	roster_changed.emit()


func capture_world(extra: Dictionary = {}) -> Dictionary:
	var agents: Array = []
	for rec in records:
		var player: PlayerScript = rec["player"]
		var row: Dictionary = player.capture_save()
		row["trait_drift"] = rec["persona"].trait_drift.duplicate(true)
		row["current_goal"] = rec["goals"].current_goal
		row["long_term_goal"] = rec["goals"].long_term_goal
		row["plan"] = rec["planning"].capture_save()
		agents.append(row)
	var payload: Dictionary = {
		"tick": _clock.current_tick() if _clock != null else 0,
		"map_width": _world.MAP_WIDTH if _world != null else 0,
		"map_height": _world.MAP_HEIGHT if _world != null else 0,
		"ground_items": _world.state.capture_ground() if _world != null and _world.state != null else [],
		"tile_overrides": _world.capture_tile_overrides() if _world != null else {},
		"events": _world.events.capture_save() if _world != null and _world.events != null else {},
		"selected_index": selected_index,
		"agents": agents,
	}
	for k in extra.keys():
		payload[k] = extra[k]
	return payload


func apply_world(data: Dictionary) -> bool:
	if data.is_empty() or _world == null or _clock == null:
		return false
	var version: int = int(data.get("version", 0))
	if version > SaveGameScript.VERSION:
		push_warning("[SaveGame] unsupported version %d" % version)
		return false
	var mw: int = int(data.get("map_width", 0))
	var mh: int = int(data.get("map_height", 0))
	if mw != _world.MAP_WIDTH or mh != _world.MAP_HEIGHT:
		push_warning("[SaveGame] map size mismatch (%dx%d vs %dx%d), ignoring world save" % [
			mw, mh, _world.MAP_WIDTH, _world.MAP_HEIGHT,
		])
		return false
	_clock.restore_tick(int(data.get("tick", 0)))
	var tiles_raw: Variant = data.get("tile_overrides", {})
	_world.restore_tile_overrides(tiles_raw if typeof(tiles_raw) == TYPE_DICTIONARY else {})
	var ground: Variant = data.get("ground_items", [])
	_world.state.restore_ground(ground if typeof(ground) == TYPE_ARRAY else [])
	var events_data: Variant = data.get("events", {})
	_world.events.restore_save(events_data if typeof(events_data) == TYPE_DICTIONARY else {})
	var agents_raw: Variant = data.get("agents", [])
	if typeof(agents_raw) != TYPE_ARRAY:
		agents_raw = []
	for row_raw in agents_raw:
		if typeof(row_raw) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = row_raw
		var rec: Dictionary = _find_record(str(row.get("id", "")))
		if rec.is_empty():
			continue
		rec["player"].apply_save(row)
		rec["persona"].trait_drift = _coerce_float_dict(row.get("trait_drift", {}))
		rec["goals"].apply_save(str(row.get("current_goal", "")), str(row.get("long_term_goal", "")))
		var plan: Variant = row.get("plan", {})
		if typeof(plan) == TYPE_DICTIONARY:
			rec["planning"].restore_save(plan)
	select_index(int(data.get("selected_index", 0)))
	return true


func _coerce_float_dict(raw: Variant) -> Dictionary:
	var out: Dictionary = {}
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	for k in raw.keys():
		out[str(k)] = float(raw[k])
	return out


func _destroy_runtime() -> void:
	for rec in records:
		if is_instance_valid(rec.get("decision")):
			rec["decision"].set_enabled(false)
		for key in ["persona", "memory", "relationships", "goals", "planning", "decision", "reflection"]:
			var node: Node = rec.get(key)
			if node != null and is_instance_valid(node) and node.get_parent() != null:
				node.get_parent().remove_child(node)
				node.free()
	records.clear()
	selected_index = 0
	if comm != null and is_instance_valid(comm):
		if comm.get_parent() != null:
			comm.get_parent().remove_child(comm)
		comm.free()
		comm = null
	if _agents_root != null:
		for child in _agents_root.get_children():
			_agents_root.remove_child(child)
			child.free()


func _spawn_agents() -> void:
	var cfgs: Array = Config.all_agents()
	var count: int = mini(Config.starting_agent_count(), cfgs.size())
	for i in count:
		var cfg: Dictionary = cfgs[i]
		var player: PlayerScript = AgentScene.instantiate()
		player.name = "Agent_%s" % str(cfg.get("id", i))
		_agents_root.add_child(player)
		player.bind_world(_world)
		player.bind_clock(_clock)
		player.bind_comm(comm)
		player.bind_observability(_logger)
		player.apply_agent_config(cfg)
		_world.register_exploration(player.exploration)
		if cfg.has("color") and typeof(cfg["color"]) == TYPE_ARRAY and cfg["color"].size() >= 3:
			var c: Array = cfg["color"]
			player.set_body_color(Color(float(c[0]), float(c[1]), float(c[2])))
		player._relocate_spawn()
		comm.register_player(player)

		var persona: PersonaScript = PersonaScript.new()
		persona.name = "Persona_%s" % player.agent_id
		_runtime_parent.add_child(persona)
		_apply_persona(persona, cfg)

		var memory: MemoryStreamScript = MemoryStreamScript.new()
		memory.name = "Memory_%s" % player.agent_id
		_runtime_parent.add_child(memory)
		memory.open(str(player.agent_id))

		var relationships: RelationshipsScript = RelationshipsScript.new()
		relationships.name = "Relationships_%s" % player.agent_id
		_runtime_parent.add_child(relationships)
		relationships.open(str(player.agent_id))

		var goals: AgentGoalsScript = AgentGoalsScript.new()
		goals.name = "Goals_%s" % player.agent_id
		_runtime_parent.add_child(goals)
		goals.open(str(player.agent_id))
		goals.seed_from_config(cfg)

		var planning: PlanningScript = PlanningScript.new()
		planning.name = "Planning_%s" % player.agent_id
		_runtime_parent.add_child(planning)

		var decision: DecisionScript = DecisionScript.new()
		decision.name = "Decision_%s" % player.agent_id
		_runtime_parent.add_child(decision)

		var reflection: ReflectionScript = ReflectionScript.new()
		reflection.name = "Reflection_%s" % player.agent_id
		_runtime_parent.add_child(reflection)

		planning.setup(player, _clock, _llm, persona, memory, comm, relationships, goals)
		planning.set_logger(_logger)
		decision.setup(player, _clock, _llm, _logger, persona, memory, comm, planning, relationships, goals)
		reflection.setup(memory, _clock, _llm, persona, str(player.agent_id))
		reflection.set_logger(_logger)

		records.append({
			"player": player,
			"persona": persona,
			"memory": memory,
			"relationships": relationships,
			"goals": goals,
			"planning": planning,
			"decision": decision,
			"reflection": reflection,
		})
	_refresh_selection_highlight()
	roster_changed.emit()


func _on_message_delivered(
	speaker_id: String,
	target_id: String,
	_text: String,
	_tick: int,
	recipient_ids: Array,
) -> void:
	var speaker_rec := _find_record(speaker_id)
	if not speaker_rec.is_empty() and target_id != "broadcast":
		speaker_rec["relationships"].on_spoke_to(target_id)
	for rid in recipient_ids:
		var listener_rec := _find_record(str(rid))
		if not listener_rec.is_empty():
			listener_rec["relationships"].on_heard_from(speaker_id)


func _on_item_given(giver_id: String, receiver_id: String, _item_id: String, _tick: int) -> void:
	var giver_rec := _find_record(giver_id)
	if not giver_rec.is_empty():
		giver_rec["relationships"].on_gave_to(receiver_id)
	var receiver_rec := _find_record(receiver_id)
	if not receiver_rec.is_empty():
		receiver_rec["relationships"].on_received_from(giver_id)


func _find_record(agent_id: String) -> Dictionary:
	for rec in records:
		if str(rec["player"].agent_id) == agent_id:
			return rec
	return {}


func _maybe_log_snapshot(tick: int) -> void:
	if _logger == null:
		return
	var interval: int = int(Config.observability_cfg().get("snapshot_interval_ticks", 25))
	if interval <= 0 or tick % interval != 0:
		return
	_logger.log_world_snapshot(tick, _build_agent_snapshots())


func _build_agent_snapshots() -> Array:
	var rows: Array = []
	for rec in records:
		var player: PlayerScript = rec["player"]
		var tile: Vector2i = player.get_tile_position()
		var region_name: String = ""
		if _world != null and _world.state != null:
			region_name = _world.state.region_name_at(tile)
		rows.append({
			"id": str(player.agent_id),
			"display_name": str(rec["persona"].display_name),
			"tile": [tile.x, tile.y],
			"region": region_name,
			"inventory": player.inventory.duplicate(),
			"state": player.busy_state(),
			"queue_len": player.queued_action_count(),
		})
	return rows


func _apply_persona(persona: PersonaScript, cfg: Dictionary) -> void:
	persona.agent_id = StringName(str(cfg.get("id", "agent")))
	persona.display_name = str(cfg.get("display_name", "Agent"))
	if cfg.has("persona") and typeof(cfg["persona"]) == TYPE_DICTIONARY:
		persona.base_traits = cfg["persona"]
	persona.starting_biography = str(cfg.get("biography", ""))


func _refresh_selection_highlight() -> void:
	for i in records.size():
		var p: PlayerScript = records[i]["player"]
		p.set_selected(i == selected_index)


func tick_co_presence() -> void:
	for rec in records:
		var observer: PlayerScript = rec["player"]
		for p in comm.players_in_perception(observer):
			if p == observer:
				continue
			rec["relationships"].on_co_presence(str(p.agent_id))
