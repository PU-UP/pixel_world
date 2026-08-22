extends Node2D
##
## Pixel World — 入口
## P3: LLM 决策闭环 + manual/agent 控制模式
##

const WorldScript = preload("res://scripts/world/world.gd")
const PlayerScript = preload("res://scripts/player.gd")
const ClockScript = preload("res://scripts/world/clock.gd")
const LlmClientScript = preload("res://scripts/llm/client.gd")
const LoggerScript = preload("res://scripts/observability/logger.gd")
const DecisionScript = preload("res://scripts/agent/decision.gd")
const PersonaScript = preload("res://scripts/agent/persona.gd")

enum ControlMode { MANUAL, AGENT }

@onready var _world: WorldScript = $World
@onready var _player: PlayerScript = $Player
@onready var _camera: Camera2D = $Camera2D
@onready var _clock: ClockScript = $GameClock
@onready var _hud: CanvasLayer = $HUD
@onready var _hud_status: Label = $HUD/VBox/StatusLabel
@onready var _hud_agent: Label = $HUD/VBox/AgentLabel
@onready var _hud_observation: Label = $HUD/VBox/ObservationLabel
@onready var _hud_action_log: Label = $HUD/VBox/ActionLogLabel
@onready var _hud_decision: Label = $HUD/VBox/DecisionLabel
@onready var _llm: LlmClientScript = $LlmClient
@onready var _logger: LoggerScript = $ObservabilityLogger
@onready var _decision: DecisionScript = $AgentDecision
@onready var _persona: PersonaScript = $Persona

var _debug_visible: bool = true
var _selected_index: int = 0
var _agents: Array[PlayerScript] = []
var _control_mode: int = ControlMode.MANUAL


func _ready() -> void:
	_player.bind_world(_world)
	_player.bind_clock(_clock)
	_camera.make_current()
	_camera.position_smoothing_enabled = true
	_hud.visible = _debug_visible
	_agents = [_player]
	_apply_persona_config()
	_decision.setup(_player, _clock, _llm, _logger, _persona)
	_set_control_mode(_control_mode_from_config())
	_decision.decision_made.connect(_on_decision_made)


func _process(_delta: float) -> void:
	_camera.global_position = _player.global_position
	if _debug_visible:
		_update_hud()


func _apply_persona_config() -> void:
	var cfg: Dictionary = Config.agent_config()
	if cfg.is_empty():
		return
	_persona.agent_id = StringName(str(cfg.get("id", "player")))
	_persona.display_name = str(cfg.get("display_name", "Player"))
	if cfg.has("persona") and typeof(cfg["persona"]) == TYPE_DICTIONARY:
		_persona.base_traits = cfg["persona"]
	_persona.starting_biography = str(cfg.get("biography", ""))


func _control_mode_from_config() -> int:
	return ControlMode.AGENT if Config.control_mode() == "agent" else ControlMode.MANUAL


func _set_control_mode(mode: int) -> void:
	_control_mode = mode
	_decision.set_enabled(mode == ControlMode.AGENT)


func _control_mode_label() -> String:
	return "AGENT" if _control_mode == ControlMode.AGENT else "MANUAL"


func _update_hud() -> void:
	var pause_str: String = "PAUSED" if _clock.paused else "RUNNING"
	var llm_str := "LLM:ok" if _llm.is_configured() else "LLM:no-key"
	_hud_status.text = "FPS: %d  tick: %d  %s  mode:%s  %s  (F1暂停 F2单步 F3切模式 ` HUD Tab切agent)" % [
		Engine.get_frames_per_second(),
		_clock.current_tick(),
		pause_str,
		_control_mode_label(),
		llm_str,
	]
	var selected: PlayerScript = _current_agent()
	if selected == null:
		_hud_agent.text = "selected: (none)"
		_hud_observation.text = ""
		_hud_action_log.text = ""
		_hud_decision.text = ""
		return
	_hud_agent.text = selected.get_status_line()
	_hud_observation.text = "observation: " + selected.get_observation()
	var lines := selected.get_action_log_lines(4)
	_hud_action_log.text = "recent actions:\n" + ("\n".join(lines) if lines.size() > 0 else "  (none)")
	_hud_decision.text = "decision: " + _decision.get_last_decision_text()


func _current_agent() -> PlayerScript:
	if _agents.is_empty():
		return null
	return _agents[_selected_index % _agents.size()]


func _on_decision_made(_tick: int, _raw: String, _action: Dictionary, _result: Dictionary) -> void:
	if _debug_visible:
		_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		_debug_visible = not _debug_visible
		_hud.visible = _debug_visible
	elif event.is_action_pressed("quit"):
		get_tree().quit()
	elif event.is_action_pressed("toggle_pause"):
		_clock.paused = not _clock.paused
	elif event.is_action_pressed("step_tick"):
		_clock.tick_once()
	elif event.is_action_pressed("toggle_agent"):
		if _agents.size() > 0:
			_selected_index = (_selected_index + 1) % _agents.size()
	elif event.is_action_pressed("toggle_control_mode"):
		_set_control_mode(ControlMode.MANUAL if _control_mode == ControlMode.AGENT else ControlMode.AGENT)
	elif _control_mode == ControlMode.MANUAL:
		if event.is_action_pressed("click_move"):
			_player.enqueue_move_to_world(get_global_mouse_position())
		elif event.is_action_pressed("move_up"):
			_try_step_input(Vector2i(0, -1))
		elif event.is_action_pressed("move_down"):
			_try_step_input(Vector2i(0, 1))
		elif event.is_action_pressed("move_left"):
			_try_step_input(Vector2i(-1, 0))
		elif event.is_action_pressed("move_right"):
			_try_step_input(Vector2i(1, 0))


func _try_step_input(delta: Vector2i) -> void:
	if _player.is_busy():
		return
	_player.enqueue_move_to_tile(_player.get_tile_position() + delta)
