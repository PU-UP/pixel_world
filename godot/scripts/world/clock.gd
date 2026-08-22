extends Node
class_name GameClock
##
## 游戏内时钟 (P1 阶段为最小骨架)。
## 真实 tick 调度 + 日夜循环留到 P3 接入 LLM 后再做。
##

signal tick(tick_index: int)

@export var tick_hz: float = 2.0  # 2 ticks / 秒 — 调 LLM 时会降

var _accumulator: float = 0.0
var _tick_index: int = 0

func _process(delta: float) -> void:
	_accumulator += delta
	var period := 1.0 / tick_hz
	while _accumulator >= period:
		_accumulator -= period
		_tick_index += 1
		tick.emit(_tick_index)

func current_tick() -> int:
	return _tick_index
