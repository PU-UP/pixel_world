extends Node
class_name GameClock
##
## 游戏内时钟 (P1 骨架,P1.5 加 paused / step)
## 真实 tick 调度 + 日夜循环留到 P3 接入 LLM 后再做。
##

signal tick(tick_index: int)

@export var tick_hz: float = 2.0  # 2 ticks / 秒 — 调 LLM 时会降

var _accumulator: float = 0.0
var _tick_index: int = 0
var paused: bool = false

func _ready() -> void:
	tick_hz = Config.tick_hz()

func _process(delta: float) -> void:
	if paused:
		return
	_advance(delta)

func _advance(delta: float) -> void:
	_accumulator += delta
	var period: float = 1.0 / tick_hz
	while _accumulator >= period:
		_accumulator -= period
		_tick_index += 1
		tick.emit(_tick_index)

func current_tick() -> int:
	return _tick_index


func reset() -> void:
	_tick_index = 0
	_accumulator = 0.0
	paused = false


# ---- P1.5: 单步 ----
func tick_once() -> void:
	# 无论 paused 与否都推进一 tick(由调用方决定何时用)
	_advance(1.0 / tick_hz)
