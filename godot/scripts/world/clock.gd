extends Node
class_name GameClock
##
## 游戏内时钟：tick 调度 + 日夜循环（由 tick 派生，续局自动接上）
##

signal tick(tick_index: int)

const PHASE_DAWN := "dawn"
const PHASE_DAY := "day"
const PHASE_DUSK := "dusk"
const PHASE_NIGHT := "night"

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


func restore_tick(tick: int) -> void:
	_tick_index = maxi(0, tick)
	_accumulator = 0.0


func tick_once() -> void:
	_advance(1.0 / tick_hz)


func time_enabled() -> bool:
	return Config.time_enabled()


func day_length() -> int:
	return Config.time_day_length_ticks()


func day_index() -> int:
	return int(_tick_index / day_length())


func cycle_progress() -> float:
	var length: int = day_length()
	return float(_tick_index % length) / float(length)


func phase() -> String:
	if not time_enabled():
		return PHASE_DAY
	var cfg: Dictionary = Config.time_cfg()
	var pos: float = cycle_progress()
	if pos < float(cfg.get("dawn_end", 0.12)):
		return PHASE_DAWN
	if pos < float(cfg.get("day_end", 0.55)):
		return PHASE_DAY
	if pos < float(cfg.get("dusk_end", 0.70)):
		return PHASE_DUSK
	return PHASE_NIGHT


func phase_zh() -> String:
	return _phase_zh(phase())


func is_night() -> bool:
	return phase() == PHASE_NIGHT


func next_dawn_tick() -> int:
	var length: int = day_length()
	return (int(_tick_index / length) + 1) * length


func next_phase() -> String:
	match phase():
		PHASE_DAWN:
			return PHASE_DAY
		PHASE_DAY:
			return PHASE_DUSK
		PHASE_DUSK:
			return PHASE_NIGHT
		_:
			return PHASE_DAWN


func next_phase_zh() -> String:
	return _phase_zh(next_phase())


static func _phase_zh(phase_id: String) -> String:
	match phase_id:
		PHASE_DAWN:
			return "黎明"
		PHASE_DUSK:
			return "黄昏"
		PHASE_NIGHT:
			return "夜晚"
		_:
			return "白天"


func phase_progress() -> float:
	if not time_enabled():
		return 1.0
	var cfg: Dictionary = Config.time_cfg()
	var dawn_end: float = float(cfg.get("dawn_end", 0.12))
	var day_end: float = float(cfg.get("day_end", 0.55))
	var dusk_end: float = float(cfg.get("dusk_end", 0.70))
	var pos: float = cycle_progress()
	var start: float = 0.0
	var end: float = dawn_end
	match phase():
		PHASE_DAY:
			start = dawn_end
			end = day_end
		PHASE_DUSK:
			start = day_end
			end = dusk_end
		PHASE_NIGHT:
			start = dusk_end
			end = 1.0
		_:
			start = 0.0
			end = dawn_end
	var span: float = end - start
	if span <= 0.0:
		return 1.0
	return clampf((pos - start) / span, 0.0, 1.0)


func format_phase_clock() -> String:
	var width: int = Config.time_phase_bar_width()
	var filled: int = clampi(int(round(phase_progress() * float(width))), 0, width)
	var bar := ""
	for i in width:
		bar += "#" if i < filled else "."
	return "%s[%s]→%s" % [phase_zh(), bar, next_phase_zh()]


func phase_tint() -> Color:
	if not time_enabled():
		return Color.WHITE
	var tints: Dictionary = Config.time_cfg().get("tint", {})
	return _color_from_cfg(tints.get(phase(), []), _fallback_tint(phase()))


static func _fallback_tint(phase_id: String) -> Color:
	match phase_id:
		PHASE_DAWN:
			return Color(1.0, 0.82, 0.68)
		PHASE_DUSK:
			return Color(0.92, 0.62, 0.48)
		PHASE_NIGHT:
			return Color(0.32, 0.38, 0.62)
		_:
			return Color.WHITE


static func _color_from_cfg(raw: Variant, fallback: Color) -> Color:
	if typeof(raw) != TYPE_ARRAY or raw.size() < 3:
		return fallback
	return Color(float(raw[0]), float(raw[1]), float(raw[2]), 1.0)
