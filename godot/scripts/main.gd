extends Node2D
##
## Pixel World — 入口
## P1 阶段: 程序生成荒岛 → 玩家能走 → 相机跟随 → 调试 HUD
##

@onready var _world: Node2D = $World
@onready var _player: CharacterBody2D = $Player
@onready var _camera: Camera2D = $Camera2D
@onready var _hud: CanvasLayer = $HUD
@onready var _label: Label = $HUD/Label
@onready var _clock: Node = $GameClock

var _debug_visible: bool = true

func _ready() -> void:
	# 玩家初始位置: 岛中心, 草地
	_player.global_position = Vector2(32 * 16, 32 * 16)
	_player.bind_world(_world)
	# 相机居中于玩家
	_camera.make_current()
	_camera.position_smoothing_enabled = true
	# 调试 HUD
	_hud.visible = _debug_visible
	_label.text = "Pixel World — P1\nWASD/方向键 移动  `  切换调试  ESC 退出"

func _process(_delta: float) -> void:
	if _debug_visible:
		var t := _player.global_position / 16.0
		_label.text = "FPS: %d  tick: %d  pos: (%.1f, %.1f)  tile: (%d, %d)" % [
			Engine.get_frames_per_second(),
			_clock.current_tick(),
			_player.global_position.x, _player.global_position.y,
			int(t.x), int(t.y),
		]

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		_debug_visible = not _debug_visible
		_hud.visible = _debug_visible
	elif event.is_action_pressed("quit"):
		get_tree().quit()
