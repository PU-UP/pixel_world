extends Node2D
##
## Pixel World — 入口
## P1: 程序生成荒岛 → 玩家能走 → 相机跟随
## P1.5: 上帝视角观测面板 + F1 暂停 / F2 单步 / Tab 切换 agent
## P2 即将: A* + MOVE_TO 原语
##

const WorldScript = preload("res://scripts/world/world.gd")
const PlayerScript = preload("res://scripts/player.gd")
const ClockScript = preload("res://scripts/world/clock.gd")

@onready var _world: WorldScript = $World
@onready var _player: PlayerScript = $Player
@onready var _camera: Camera2D = $Camera2D
@onready var _clock: ClockScript = $GameClock
@onready var _hud: CanvasLayer = $HUD
@onready var _hud_status: Label = $HUD/VBox/StatusLabel
@onready var _hud_agent: Label = $HUD/VBox/AgentLabel
@onready var _hud_observation: Label = $HUD/VBox/ObservationLabel
@onready var _hud_action_log: Label = $HUD/VBox/ActionLogLabel

# ---- P1.5 状态 ----
var _debug_visible: bool = true
var _selected_index: int = 0   # 暂时锁 0,Tab 切换在 P5 多 agent 时启用
var _agents: Array[PlayerScript] = []   # 所有可被选中的 agent (P1 阶段只有 player)

func _ready() -> void:
	# 玩家初始位置: 岛中心, 草地
	_player.global_position = Vector2(32 * 16, 32 * 16)
	_player.bind_world(_world)
	_player.bind_clock(_clock)
	# 相机居中于玩家
	_camera.make_current()
	_camera.position_smoothing_enabled = true
	# 调试 HUD
	_hud.visible = _debug_visible
	# 注册 agent(暂时只有 player;P5 多 agent 改成加载 agents.yaml)
	_agents = [_player]

func _process(_delta: float) -> void:
	if _debug_visible:
		_update_hud()

func _update_hud() -> void:
	var pause_str := "PAUSED" if _clock.paused else "RUNNING"
	_hud_status.text = "FPS: %d  tick: %d  %s  (F1 暂停 / F2 单步 / ` 隐藏 HUD / Tab 切 agent)" % [
		Engine.get_frames_per_second(),
		_clock.current_tick(),
		pause_str,
	]
	var selected: PlayerScript = _current_agent()
	if selected == null:
		_hud_agent.text = "selected: (none)"
		_hud_observation.text = ""
		_hud_action_log.text = ""
		return
	_hud_agent.text = selected.get_status_line()
	_hud_observation.text = "observation: " + selected.get_observation()
	var lines := selected.get_action_log_lines(4)
	_hud_action_log.text = "recent actions:\n" + ("\n".join(lines) if lines.size() > 0 else "  (none)")

func _current_agent() -> PlayerScript:
	if _agents.is_empty():
		return null
	var i: int = _selected_index % _agents.size()
	return _agents[i]

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		_debug_visible = not _debug_visible
		_hud.visible = _debug_visible
	elif event.is_action_pressed("quit"):
		get_tree().quit()
	elif event.is_action_pressed("toggle_pause"):
		_clock.paused = not _clock.paused
	elif event.is_action_pressed("step_tick"):
		# 单步:推一 tick(玩家可继续移动,但 World tick 推进一格)
		_clock.tick_once()
	elif event.is_action_pressed("toggle_agent"):
		# Tab 切换(暂时只在 1 个 agent 内部循环,P5 多 agent 时扩成多选)
		if _agents.size() > 0:
			_selected_index = (_selected_index + 1) % _agents.size()
