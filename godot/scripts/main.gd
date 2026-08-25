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
const CameraRigScript = preload("res://scripts/ui/camera_rig.gd")
const FogOfWarScript = preload("res://scripts/ui/fog_of_war.gd")
const ExplorationMap = preload("res://scripts/world/exploration_map.gd")
const SaveGameScript = preload("res://scripts/world/save_game.gd")

enum ControlMode { MANUAL, AGENT }

@onready var _world: WorldScript = $World
@onready var _agents_root: Node2D = $Agents
@onready var _coordinator: CoordinatorScript = $AgentCoordinator
@onready var _camera: CameraRigScript = $Camera2D
@onready var _clock: ClockScript = $GameClock
@onready var _hud: CanvasLayer = $HUD
@onready var _hud_root: Control = $HUD/Root
@onready var _hud_status: Label = $HUD/Root/HBox/ObservePanel/ObserveVBox/StatusLabel
@onready var _hud_agent: Label = $HUD/Root/HBox/ObservePanel/ObserveVBox/AgentLabel
@onready var _hud_observation: Label = $HUD/Root/HBox/ObservePanel/ObserveVBox/ObsScroll/ObservationLabel
@onready var _hud_action_log: Label = $HUD/Root/HBox/ObservePanel/ObserveVBox/ActionScroll/ActionLogLabel
@onready var _hud_decision: Label = $HUD/Root/HBox/ObservePanel/ObserveVBox/DecisionScroll/DecisionLabel
@onready var _obs_scroll: ScrollContainer = $HUD/Root/HBox/ObservePanel/ObserveVBox/ObsScroll
@onready var _action_scroll: ScrollContainer = $HUD/Root/HBox/ObservePanel/ObserveVBox/ActionScroll
@onready var _decision_scroll: ScrollContainer = $HUD/Root/HBox/ObservePanel/ObserveVBox/DecisionScroll
@onready var _hud_roster: Label = $HUD/Root/HBox/ObservePanel/ObserveVBox/RosterScroll/RosterLabel
@onready var _roster_scroll: ScrollContainer = $HUD/Root/HBox/ObservePanel/ObserveVBox/RosterScroll
@onready var _roster_header: Label = $HUD/Root/HBox/ObservePanel/ObserveVBox/RosterHeader
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
var _observe_details_visible: bool = true
var _god_view: bool = true
var _continued: bool = false
var _fog: FogOfWarLayer = null


func _ready() -> void:
	_camera.make_current()
	_camera.position_smoothing_enabled = true
	_agents_root.z_index = 10
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
	_fog = FogOfWarScript.new()
	_fog.name = "FogOfWar"
	add_child(_fog)
	move_child(_fog, _agents_root.get_index())
	_fog.setup(_world)
	_camera.set_world_center(_world.world_size() * 0.5)
	_god_view = Config.observer_default_god()
	var loaded_control: String = _try_load_save()
	if loaded_control == "agent":
		_set_control_mode(ControlMode.AGENT)
	elif loaded_control == "manual":
		_set_control_mode(ControlMode.MANUAL)
	else:
		_set_control_mode(_control_mode_from_config())
	_hud_status.gui_input.connect(_on_status_label_gui_input)
	_apply_observe_details_visibility()
	if not _clock.tick.is_connected(_on_clock_save_tick):
		_clock.tick.connect(_on_clock_save_tick)
	get_tree().set_auto_accept_quit(false)
	if _god_view:
		_camera.fit_world(_world.world_size())
	_update_view_mode()


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
	_logger.log_world_event_logged(event_id, text, tick)


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
	_update_view_mode()
	_apply_entity_visibility()
	var agent := _current_agent()
	_camera.set_follow_target(agent)
	_camera.apply_follow()
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
	var mode := "自主" if _control_mode == ControlMode.AGENT else "手动·F3自主"
	if _god_view:
		return "%s·上帝" % mode
	return "%s·跟随" % mode


func _observer_rules_label() -> String:
	var parts: PackedStringArray = PackedStringArray()
	if Config.perception_los_enabled():
		parts.append("LOS")
	if _god_view and Config.observer_god_vision_overlay():
		parts.append("光圈")
	elif not _god_view:
		parts.append("跟随迷雾")
	parts.append("续局" if _continued else "新局")
	return "规则:%s" % "·".join(parts)


func _update_view_mode() -> void:
	if _fog == null:
		return
	var agent := _current_agent()
	if agent != null:
		_fog.set_exploration(agent.exploration)
		_fog.set_vision_focus(agent.get_tile_position(), agent.observation_radius_tiles)
	if _god_view:
		_fog.set_god_mode(true)
		_camera.set_view_mode(CameraRigScript.ViewMode.GOD_MAP)
		_world.set_view_filter(null, true)
	else:
		_fog.set_god_mode(false)
		_camera.set_view_mode(CameraRigScript.ViewMode.FOLLOW_AGENT)
		if agent != null:
			_world.set_view_filter(agent.exploration, false)
	_minimap.set_god_mode(_god_view)
	if not _god_view and agent != null:
		_minimap.set_exploration(agent.exploration)


func _apply_entity_visibility() -> void:
	if _god_view:
		for rec in _coordinator.records:
			var p: PlayerScript = rec["player"]
			if p != null and is_instance_valid(p):
				p.visible = true
		return
	var observer := _current_agent()
	if observer == null or observer.exploration == null:
		return
	for rec in _coordinator.records:
		var p: PlayerScript = rec["player"]
		if p == null or not is_instance_valid(p):
			continue
		if p == observer:
			p.visible = true
			continue
		var t: Vector2i = p.get_tile_position()
		p.visible = observer.exploration.get_state(t.x, t.y) == ExplorationMap.TileVis.VISIBLE


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
	var pause_str: String = "暂停" if _clock.paused else "运行"
	var llm_str := "LLM:未配置"
	if _llm.is_configured():
		llm_str = "LLM:%d/%d" % [_llm.inflight_count(), _llm.inflight_count() + _llm.queue_length()]
	var tok: int = int(_logger.stats().get("tokens_total", 0))
	var roster: String = "%d/%d" % [_coordinator.selected_index + 1, _coordinator.spawn_count()]
	var zoom_pct: int = int(round(_camera.zoom.x * 100.0))
	var selected: PlayerScript = _current_agent()
	var vis_n := 0
	if selected != null and selected.exploration != null:
		vis_n = selected.exploration.visible_count()
	var status_core := "帧率:%d  tick:%d  %s  %s  %s  token:%d  角色#%s  视野:%d  缩放:%d%%  %s" % [
		Engine.get_frames_per_second(),
		_clock.current_tick(),
		pause_str,
		_control_mode_label(),
		llm_str,
		tok,
		roster,
		vis_n,
		zoom_pct,
		_observer_rules_label(),
	]
	if not _observe_details_visible:
		_hud_status.text = "【点击展开】%s" % status_core
		return
	_hud_status.text = "【点击收起】%s" % status_core
	if selected == null:
		_hud_agent.text = "角色：（无）"
		_hud_observation.text = "（无）"
		_hud_action_log.text = "（无）"
		_hud_decision.text = "（无）"
		_update_roster_hud()
		return
	var rec := _selected_record()
	var name_prefix := str(rec["persona"].display_name) if not rec.is_empty() else str(selected.agent_id)
	_hud_agent.text = "%s | %s" % [name_prefix, selected.get_status_line()]
	_hud_observation.text = "观察：%s" % selected.get_observation()
	var lines := selected.get_action_log_lines(4)
	_hud_action_log.text = "\n".join(lines) if lines.size() > 0 else "（无）"
	var decision := _selected_decision()
	var decision_text := decision.get_last_decision_text() if decision != null else "（无）"
	_hud_decision.text = "决策：%s" % decision_text
	_update_roster_hud()


func _update_roster_hud() -> void:
	if _hud_roster == null:
		return
	if _roster_header != null:
		_roster_header.text = "全员 · 选中视野 可见/遮挡/超距"
	var lines: PackedStringArray = PackedStringArray()
	var observer := _current_agent()
	for rec in _coordinator.records:
		var p: PlayerScript = rec["player"]
		if p == null or not is_instance_valid(p):
			continue
		var tile: Vector2i = p.get_tile_position()
		var region := "荒野"
		if _world != null and _world.state != null:
			region = _world.state.region_name_at(tile)
		var mark := " "
		if p == observer:
			mark = ">"
		var vis := _roster_vis_label(observer, p, tile)
		var goal := ""
		if rec.has("goals"):
			goal = str(rec["goals"].current_goal)
			if goal.length() > 18:
				goal = goal.substr(0, 17) + "…"
		var name_s: String = str(rec["persona"].display_name)
		lines.append("%s%s %s (%d,%d) %s %s" % [
			mark, name_s, p.busy_state(), tile.x, tile.y, region, vis,
		])
		if not goal.is_empty():
			lines.append("  %s" % goal)
	_hud_roster.text = "\n".join(lines) if lines.size() > 0 else "（无）"


func _roster_vis_label(observer: PlayerScript, p: PlayerScript, tile: Vector2i) -> String:
	if observer == null or observer.exploration == null:
		return "?"
	if p == observer:
		return "自己"
	var st: int = observer.exploration.get_state(tile.x, tile.y)
	if st == ExplorationMap.TileVis.VISIBLE:
		return "可见"
	var r: int = observer.observation_radius_tiles
	var ot: Vector2i = observer.get_tile_position()
	var dx: int = tile.x - ot.x
	var dy: int = tile.y - ot.y
	if dx * dx + dy * dy <= r * r:
		return "遮挡"
	return "超距"


func _update_memory_hud() -> void:
	var rec := _selected_record()
	if rec.is_empty():
		_hud_memory_title.text = "记忆（F4 关闭）"
		_hud_reflection.text = "（无）"
		_hud_memory.text = "（空）"
		return
	var player: PlayerScript = rec["player"]
	var persona = rec["persona"]
	var agent_label := "%s" % str(player.agent_id)
	_hud_memory_title.text = "记忆 — %s（%s）  Tab切换  F4关闭" % [persona.display_name, agent_label]
	var limit: int = int(Config.memory_cfg().get("hud", {}).get("display_limit", 50))
	_hud_reflection.text = rec["reflection"].get_last_reflection_text()
	_hud_memory.text = rec["memory"].format_for_hud(limit, "[%s]" % agent_label)


func _update_relation_hud() -> void:
	var rec := _selected_record()
	if rec.is_empty():
		_hud_relation_title.text = "关系（F5 关闭）"
		_hud_plan.text = "（无）"
		_hud_relations.text = "（空）"
		return
	var player: PlayerScript = rec["player"]
	var persona = rec["persona"]
	var agent_label := str(player.agent_id)
	_hud_relation_title.text = "关系 — %s（%s）  F5关闭" % [persona.display_name, agent_label]
	var plan_steps: PackedStringArray = rec["planning"].get_remaining_steps()
	var goal_text: String = rec["goals"].format_for_prompt() if rec.has("goals") else ""
	var plan_header := ""
	if not goal_text.is_empty():
		plan_header = goal_text + "\n\n"
	if plan_steps.is_empty():
		_hud_plan.text = _truncate(plan_header + rec["planning"].get_last_plan_text(), 220)
	else:
		_hud_plan.text = _truncate(plan_header + "\n".join(plan_steps), 220)
	var rel_text: String = rec["relationships"].format_for_hud(_coordinator.all_agent_ids())
	var network: String = rec["relationships"].format_network_ascii(_coordinator.all_agent_ids())
	_hud_relations.text = "%s\n\n%s" % [network, rel_text]


func _truncate(text: String, max_len: int) -> String:
	if text.length() <= max_len:
		return text
	return text.substr(0, max_len - 1) + "…"


func _on_status_label_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_observe_details_visible = not _observe_details_visible
		_apply_observe_details_visibility()
		if _debug_visible:
			_update_hud()


func _apply_observe_details_visibility() -> void:
	var show := _observe_details_visible and _debug_visible
	_hud_agent.visible = show
	_obs_scroll.visible = show
	_action_scroll.visible = show
	_decision_scroll.visible = show
	if _roster_scroll != null:
		_roster_scroll.visible = show
	if _roster_header != null:
		_roster_header.visible = show


func _input(event: InputEvent) -> void:
	if _camera.handle_input(event):
		get_viewport().set_input_as_handled()


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
		_apply_observe_details_visibility()
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
		_save_world()
		_logger.write_session_summary({"exit": "user_quit"})
		get_tree().quit()
	elif event.is_action_pressed("reset_world"):
		_reset_world()
	elif event.is_action_pressed("toggle_god_view"):
		_god_view = not _god_view
		_camera.reset_view()
		if _god_view:
			_camera.fit_world(_world.world_size())
		_update_view_mode()
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


func _try_load_save() -> String:
	var data: Dictionary = SaveGameScript.read()
	if data.is_empty():
		_continued = false
		return ""
	if not _coordinator.apply_world(data):
		_continued = false
		return ""
	_continued = true
	if data.has("god_view"):
		_god_view = bool(data.get("god_view", true))
	return str(data.get("control_mode", "")).strip_edges()


func _on_clock_save_tick(tick: int) -> void:
	var interval: int = SaveGameScript.autosave_ticks()
	if interval <= 0:
		return
	if tick % interval == 0:
		_save_world()


func _save_world() -> void:
	SaveGameScript.write(_coordinator.capture_world({
		"god_view": _god_view,
		"control_mode": "agent" if _control_mode == ControlMode.AGENT else "manual",
	}))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_world()
		_logger.write_session_summary({"exit": "window_close"})
		get_tree().quit()


func _reset_world() -> void:
	_llm.cancel_pending()
	_logger.rotate_session("world_reset")
	_continued = false
	var keep_agent_mode := _control_mode == ControlMode.AGENT
	_coordinator.reset_world(keep_agent_mode)
	_connect_decision_signals()
	_set_control_mode(ControlMode.AGENT if keep_agent_mode else ControlMode.MANUAL)
	if _debug_visible:
		_update_hud()
	if _memory_visible:
		_update_memory_hud()
	if _relation_visible:
		_update_relation_hud()
	_refresh_minimap()
	_camera.reset_view()
	_god_view = Config.observer_default_god()
	if _god_view:
		_camera.fit_world(_world.world_size())
	_update_view_mode()
