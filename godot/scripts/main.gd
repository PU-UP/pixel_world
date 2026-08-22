extends Node2D
##
## Pixel World — 入口
## P1:   程序生成荒岛 → 玩家能走 → 相机跟随
## P1.5: 上帝视角观测面板 + F1 暂停 / F2 单步 / Tab 切换 agent
## P2:   鼠标点哪走哪 — 点击 → MOVE_TO → A* → 沿路径走
## P3:   LLM 决策闭环
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
var _selected_index: int = 0
var _agents: Array[PlayerScript] = []

func _ready() -> void:
	_player.bind_world(_world)
	_player.bind_clock(_clock)
	_camera.make_current()
	_camera.position_smoothing_enabled = true
	_hud.visible = _debug_visible
	_agents = [_player]

func _process(_delta: float) -> void:
	if _debug_visible:
		_update_hud()

func _update_hud() -> void:
	var pause_str: String = "PAUSED" if _clock.paused else "RUNNING"
	_hud_status.text = "FPS: %d  tick: %d  %s  (F1 暂停 / F2 单步 / ` 隐藏 HUD / Tab 切 agent / 鼠标点走)" % [
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
		_clock.tick_once()
	elif event.is_action_pressed("toggle_agent"):
		if _agents.size() > 0:
			_selected_index = (_selected_index + 1) % _agents.size()
	elif event.is_action_pressed("click_move"):
		# P2: 鼠标点击 = 地图上的瓦片 → MOVE_TO
		var mp: Vector2 = event.position
		if _player._state == PlayerScript.State.WALKING:
			# 已经在走, 把新目标追加到队列 (玩家可中途改主意)
			_player.enqueue_move_to_world(mp)
		else:
			_player.enqueue_move_to_world(mp)
	elif event.is_action_pressed("move_up"):
		_try_step_input(Vector2i(0, -1))
	elif event.is_action_pressed("move_down"):
		_try_step_input(Vector2i(0, 1))
	elif event.is_action_pressed("move_left"):
		_try_step_input(Vector2i(-1, 0))
	elif event.is_action_pressed("move_right"):
		_try_step_input(Vector2i(1, 0))

## WASD = 移动 1 瓦片 — 走完才接收下一 key
func _try_step_input(delta: Vector2i) -> void:
	# 玩家在 WALKING 时不响应新方向 (避免和路径冲突)
	# 玩家可以连按多次: 走完当前步接下一步
	if _player._state == PlayerScript.State.WALKING:
		return
	var cur := Vector2i(int(floor(_player.global_position.x / PlayerScript.TILE_SIZE)),
						int(floor(_player.global_position.y / PlayerScript.TILE_SIZE)))
	var next_tile: Vector2i = cur + delta
	# 在外面或不可走: 静默忽略 (log reject)
	_player.enqueue_move_to_tile(next_tile)
