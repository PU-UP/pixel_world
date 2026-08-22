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
const AgentScene = preload("res://scenes/entities/Agent.tscn")

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


func _on_clock_tick(_t: int) -> void:
	_co_presence_counter += 1
	if _co_presence_counter >= 10:
		_co_presence_counter = 0
		tick_co_presence()


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
		player.apply_agent_config(cfg)
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

		var planning: PlanningScript = PlanningScript.new()
		planning.name = "Planning_%s" % player.agent_id
		_runtime_parent.add_child(planning)

		var decision: DecisionScript = DecisionScript.new()
		decision.name = "Decision_%s" % player.agent_id
		_runtime_parent.add_child(decision)

		var reflection: ReflectionScript = ReflectionScript.new()
		reflection.name = "Reflection_%s" % player.agent_id
		_runtime_parent.add_child(reflection)

		planning.setup(player, _clock, _llm, persona, memory, comm, relationships)
		decision.setup(player, _clock, _llm, _logger, persona, memory, comm, planning, relationships)
		reflection.setup(memory, _clock, _llm, persona, str(player.agent_id))

		records.append({
			"player": player,
			"persona": persona,
			"memory": memory,
			"relationships": relationships,
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
