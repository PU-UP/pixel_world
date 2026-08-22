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
	_spawn_agents()


func spawn_count() -> int:
	return records.size()


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

		var decision: DecisionScript = DecisionScript.new()
		decision.name = "Decision_%s" % player.agent_id
		_runtime_parent.add_child(decision)
		decision.setup(player, _clock, _llm, _logger, persona, memory, comm)

		var reflection: ReflectionScript = ReflectionScript.new()
		reflection.name = "Reflection_%s" % player.agent_id
		_runtime_parent.add_child(reflection)
		reflection.setup(memory, _clock, _llm, persona, str(player.agent_id))

		records.append({
			"player": player,
			"persona": persona,
			"memory": memory,
			"decision": decision,
			"reflection": reflection,
		})
	_refresh_selection_highlight()
	roster_changed.emit()


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
