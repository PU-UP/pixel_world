extends Node2D
##
## Pixel World — 入口
## P6: 规划 + 关系 + 性格漂移
##

const WorldScript = preload("res://scripts/world/world.gd")
const PlayerScript = preload("res://scripts/player.gd")
const ClockScript = preload("res://scripts/world/clock.gd")
const LlmClientScript = preload("res://scripts/llm/client.gd")
const LoggerScript = preload("res://scripts/observability/logger.gd")
const CoordinatorScript = preload("res://scripts/agent/coordinator.gd")
const DecisionScript = preload("res://scripts/agent/decision.gd")
const MinimapScript = preload("res://scripts/ui/minimap.gd")

enum ControlMode { MANUAL, AGENT }

@onready var _world: WorldScript = $World
@onready var _agents_root: Node2D = $Agents
@onready var _coordinator: CoordinatorScript = $AgentCoordinator
@onready var _camera: Camera2D = $Camera2D
@onready var _clock: ClockScript = $GameClock
@onready var _hud: CanvasLayer = $HUD
@onready var _hud_root: Control = $HUD/Root
@onready var _hud_status: Label = $HUD/Root/HBox/ObservePanel/ObserveVBox/StatusLabel
@onready var _hud_agent: Label = $HUD/Root/HBox/ObservePanel/ObserveVBox/AgentLabel
@onready var _hud_observation: Label = $HUD/Root/HBox/ObservePanel/ObserveVBox/ObsScroll/ObservationLabel
@onready var _hud_action_log: Label = $HUD/Root/HBox/ObservePanel/ObserveVBox/ActionScroll/ActionLogLabel
@onready var _hud_decision: Label = $HUD/Root/HBox/ObservePanel/ObserveVBox/DecisionScroll/DecisionLabel
@onready var _memory_panel: PanelContainer = $HUD/Root/HBox/MemoryPanel
@onready var _hud_memory_title: Label = $HUD/Root/HBox/MemoryPanel/MemoryVBox/MemoryHeader/MemoryTitle
@onready var _hud_reflection: Label = $HUD/Root/HBox/MemoryPanel/MemoryVBox/ReflectionScroll/ReflectionLabel
@onready var _hud_memory: Label = $HUD/Root/HBox/MemoryPanel/MemoryVBox/MemoryScroll/MemoryLabel
@onready var _relation_panel: PanelContainer = $HUD/Root/HBox/RelationPanel
@onready var _hud_relation_title: Label = $HUD/Root/HBox/RelationPanel/RelationVBox/RelationHeader/RelationTitle
@onready var _hud_plan: Label = $HUD/Root/HBox/RelationPanel/RelationVBox/PlanScroll/PlanLabel
@onready var _hud_relations: Label = $HUD/Root/HBox/RelationPanel/RelationVBox/RelationScroll/RelationLabel
@onready var _llm: LlmClientScript = $LlmClient
@onready var _logger: LoggerScript = $ObservabilityLogger
@onready var _minimap: MinimapScript = $HUD/MinimapPanel

var _debug_visible: bool = true
var _memory_visible: bool = false
var _relation_visible: bool = false
var _minimap_visible: bool = false
var _control_mode: int = ControlMode.MANUAL


func _ready() -> void:
	_camera.make_current()
	_camera.position_smoothing_enabled = true
	_hud.visible = _debug_visible
	_memory_panel.visible = _memory_visible
	_relation_panel.visible = _relation_visible
	_minimap.setup(_world)
	_minimap.visible = _minimap_visible and _debug_visible
	_coordinator.setup(_world, _clock, _llm, _logger, _agents_root, self)
	_llm.set_logger(_logger)
	_world.events.setup(_world, _clock)
	if not _world.events.event_fired.is_connected(_on_world_event):
		_world.events.event_fired.connect(_on_world_event)
	_coordinator.roster_changed.connect(_on_roster_changed)
	_connect_decision_signals()
	_set_control_mode(_control_mode_from_config())


func _connect_decision_signals() -> void:
	for rec in _coordinator.records:
		var decision: DecisionScript = rec["decision"]
		if not decision.decision_made.is_connected(_on_decision_made):
			decision.decision_made.connect(_on_decision_made)
		if not rec["reflection"].reflection_done.is_connected(_on_reflection_done):
			rec["reflection"].reflection_done.connect(_on_reflection_done)
		if not rec["planning"].plan_updated.is_connected(_on_plan_updated):
			rec["planning"].plan_updated.connect(_on_plan_updated)


func _on_world_event(event_id: String, text: String, tick: int) -> void:
	_logger.log_event("world_event", {"event_id": event_id, "text": text, "tick": tick})


func _on_roster_changed() -> void:
	_connect_decision_signals()
	if _debug_visible:
		_update_hud()
	if _memory_visible:
		_update_memory_hud()
	if _relation_visible:
		_update_relation_hud()
	_refresh_minimap()


func _process(_delta: float) -> void:
	var agent := _current_agent()
	if agent != null:
		_camera.global_position = agent.global_position
	if _debug_visible:
		_update_hud()
	if _memory_visible:
		_update_memory_hud()
	if _relation_visible:
		_update_relation_hud()
	_refresh_minimap()


func _control_mode_from_config() -> int:
	return ControlMode.AGENT if Config.control_mode() == "agent" else ControlMode.MANUAL


func _set_control_mode(mode: int) -> void:
	_control_mode = mode
	_coordinator.set_agent_mode(mode == ControlMode.AGENT)


func _control_mode_label() -> String:
	return "AGENT" if _control_mode == ControlMode.AGENT else "MANUAL"


func _selected_record() -> Dictionary:
	return _coordinator.selected_record()


func _current_agent() -> PlayerScript:
	var rec := _selected_record()
	if rec.is_empty():
		return null
	return rec["player"]


func _selected_decision() -> DecisionScript:
	var rec := _selected_record()
	if rec.is_empty():
		return null
	return rec["decision"]


func _refresh_minimap() -> void:
	if not _minimap_visible or _minimap == null:
		return
	var agents: Array = []
	for rec in _coordinator.records:
		agents.append(rec["player"])
	_minimap.set_agents(agents)


func _update_hud() -> void:
	var pause_str: String = "PAUSED" if _clock.paused else "RUNNING"
	var llm_str := "LLM:ok" if _llm.is_configured() else "LLM:no-key"
	if _llm.is_configured():
		llm_str = "LLM:%d/%d" % [_llm.inflight_count(), _llm.inflight_count() + _llm.queue_length()]
	var tok: int = int(_logger.stats().get("tokens_total", 0))
	var roster: String = "%d/%d" % [_coordinator.selected_index + 1, _coordinator.spawn_count()]
	_hud_status.text = "FPS:%d tick:%d %s %s %s tok:%d #%s" % [
		Engine.get_frames_per_second(),
		_clock.current_tick(),
		pause_str,
		_control_mode_label(),
		llm_str,
		tok,
		roster,
	]
	var selected: PlayerScript = _current_agent()
	if selected == null:
		_hud_agent.text = "agent: (none)"
		_hud_observation.text = "(none)"
		_hud_action_log.text = "(none)"
		_hud_decision.text = "(none)"
		return
	var rec := _selected_record()
	var name_prefix := str(rec["persona"].display_name) if not rec.is_empty() else str(selected.agent_id)
	_hud_agent.text = _truncate("%s | %s" % [name_prefix, selected.get_status_line()], 48)
	_hud_observation.text = "obs: %s" % _truncate(selected.get_observation(), 64)
	var lines := selected.get_action_log_lines(3)
	_hud_action_log.text = "\n".join(lines) if lines.size() > 0 else "(none)"
	var decision := _selected_decision()
	var decision_text := decision.get_last_decision_text() if decision != null else "(none)"
	_hud_decision.text = _truncate(decision_text, 100)


func _update_memory_hud() -> void:
	var rec := _selected_record()
	if rec.is_empty():
		_hud_memory_title.text = "MEMORY  (F4 close)"
		_hud_reflection.text = "(none)"
		_hud_memory.text = "(empty)"
		return
	var player: PlayerScript = rec["player"]
	var persona = rec["persona"]
	var agent_label := "%s" % str(player.agent_id)
	_hud_memory_title.text = "MEMORY — %s (%s)  Tab切换  F4关闭" % [persona.display_name, agent_label]
	var limit: int = int(Config.memory_cfg().get("hud", {}).get("display_limit", 50))
	_hud_reflection.text = _truncate(rec["reflection"].get_last_reflection_text(), 400)
	_hud_memory.text = rec["memory"].format_for_hud(limit, "[%s]" % agent_label)


func _update_relation_hud() -> void:
	var rec := _selected_record()
	if rec.is_empty():
		_hud_relation_title.text = "RELATIONS  (F5 close)"
		_hud_plan.text = "(none)"
		_hud_relations.text = "(empty)"
		return
	var player: PlayerScript = rec["player"]
	var persona = rec["persona"]
	var agent_label := str(player.agent_id)
	_hud_relation_title.text = "REL — %s (%s)  F5" % [persona.display_name, agent_label]
	var plan_steps: PackedStringArray = rec["planning"].get_remaining_steps()
	if plan_steps.is_empty():
		_hud_plan.text = _truncate(rec["planning"].get_last_plan_text(), 200)
	else:
		_hud_plan.text = _truncate("\n".join(plan_steps), 200)
	var rel_text: String = rec["relationships"].format_for_hud(_coordinator.all_agent_ids())
	var network: String = rec["relationships"].format_network_ascii(_coordinator.all_agent_ids())
	_hud_relations.text = "%s\n\n%s" % [network, rel_text]


func _truncate(text: String, max_len: int) -> String:
	if text.length() <= max_len:
		return text
	return text.substr(0, max_len - 1) + "…"


func _on_decision_made(_tick: int, _raw: String, _action: Dictionary, _result: Dictionary) -> void:
	if _debug_visible:
		_update_hud()
	if _memory_visible:
		_update_memory_hud()
	if _relation_visible:
		_update_relation_hud()
	_refresh_minimap()


func _on_reflection_done(_tick: int, _text: String) -> void:
	if _memory_visible:
		_update_memory_hud()
	if _relation_visible:
		_update_relation_hud()
	_refresh_minimap()


func _on_plan_updated(_tick: int, _steps: Array) -> void:
	if _relation_visible:
		_update_relation_hud()
	_refresh_minimap()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		_debug_visible = not _debug_visible
		_hud.visible = _debug_visible
		if not _debug_visible:
			_memory_panel.visible = false
			_relation_panel.visible = false
			_minimap.visible = false
		else:
			_memory_panel.visible = _memory_visible
			_relation_panel.visible = _relation_visible
			_minimap.visible = _minimap_visible
	elif event.is_action_pressed("toggle_minimap"):
		_minimap_visible = not _minimap_visible
		_minimap.visible = _minimap_visible and _debug_visible
		if _minimap_visible:
			_refresh_minimap()
	elif event.is_action_pressed("toggle_memory"):
		_memory_visible = not _memory_visible
		_memory_panel.visible = _memory_visible and _debug_visible
		if _memory_visible:
			_update_memory_hud()
	elif event.is_action_pressed("toggle_relationships"):
		_relation_visible = not _relation_visible
		_relation_panel.visible = _relation_visible and _debug_visible
		if _relation_visible:
			_update_relation_hud()
	elif event.is_action_pressed("quit"):
		_logger.write_session_summary({"exit": "user_quit"})
		get_tree().quit()
	elif event.is_action_pressed("toggle_pause"):
		_clock.paused = not _clock.paused
	elif event.is_action_pressed("step_tick"):
		_clock.tick_once()
	elif event.is_action_pressed("toggle_agent"):
		_coordinator.cycle_selection()
		if _memory_visible:
			_update_memory_hud()
		if _relation_visible:
			_update_relation_hud()
	elif event.is_action_pressed("toggle_control_mode"):
		_set_control_mode(ControlMode.MANUAL if _control_mode == ControlMode.AGENT else ControlMode.AGENT)
	elif _control_mode == ControlMode.MANUAL:
		var agent := _current_agent()
		if agent == null:
			return
		if event.is_action_pressed("click_move"):
			agent.enqueue_move_to_world(get_global_mouse_position())
		elif event.is_action_pressed("move_up"):
			_try_step_input(agent, Vector2i(0, -1))
		elif event.is_action_pressed("move_down"):
			_try_step_input(agent, Vector2i(0, 1))
		elif event.is_action_pressed("move_left"):
			_try_step_input(agent, Vector2i(-1, 0))
		elif event.is_action_pressed("move_right"):
			_try_step_input(agent, Vector2i(1, 0))


func _try_step_input(agent: PlayerScript, delta: Vector2i) -> void:
	if agent.is_busy():
		return
	agent.enqueue_move_to_tile(agent.get_tile_position() + delta)
