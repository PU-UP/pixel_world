extends RefCounted
class_name AgentVitals
##
## 精力 / 饱腹 / 健康 — 当前值 + 可被睡眠债/断食债压低的上限
## 结算与衰减都在代码里；数字走 config/runtime.yaml → vitals
##

var energy: float = 100.0
var satiety: float = 100.0
var energy_ceiling: float = 100.0
var satiety_ceiling: float = 100.0
var health: float = 100.0
var nights_without_sleep: int = 0
var days_without_food: int = 0
var ate_this_day: bool = false
var night_sleep_ticks: int = 0
var last_day_index: int = 0


func reset() -> void:
	var base: float = _base_max()
	energy = base
	satiety = base
	energy_ceiling = base
	satiety_ceiling = base
	health = _health_max()
	nights_without_sleep = 0
	days_without_food = 0
	ate_this_day = false
	night_sleep_ticks = 0
	last_day_index = 0


func enabled() -> bool:
	return Config.vitals_enabled()


func is_deceased() -> bool:
	return enabled() and health <= 0.0


func on_tick(day_index: int, phase: String, is_sleeping: bool, is_walking: bool) -> void:
	if not enabled() or is_deceased():
		return
	if is_sleeping:
		_tick_sleep(phase)
	else:
		_tick_awake(phase, is_walking)
	if day_index > last_day_index:
		if day_index - last_day_index > 1:
			last_day_index = day_index
			night_sleep_ticks = 0
			ate_this_day = false
		else:
			_settle_new_day(day_index)
	_clamp_to_ceilings()


func eat(satiety_restore: float, energy_restore: float) -> Dictionary:
	if not enabled() or is_deceased():
		return {"ok": false, "applied": false}
	var s0: float = satiety
	var e0: float = energy
	satiety = minf(satiety_ceiling, satiety + maxf(0.0, satiety_restore))
	energy = minf(energy_ceiling, energy + maxf(0.0, energy_restore))
	ate_this_day = true
	return {
		"ok": true,
		"applied": true,
		"satiety_delta": satiety - s0,
		"energy_delta": energy - e0,
	}


func move_speed_scale() -> float:
	if not enabled() or is_deceased():
		return 1.0
	var cfg: Dictionary = Config.vitals_cfg()
	var scale: float = 1.0
	var below: float = float(cfg.get("low_energy_speed_below", 18))
	if energy < below:
		scale *= clampf(float(cfg.get("low_energy_speed_scale", 0.72)), 0.4, 1.0)
	var hcfg: Dictionary = _health_cfg()
	if health < float(hcfg.get("slow_below", 20)):
		scale *= clampf(float(hcfg.get("slow_scale", 0.8)), 0.4, 1.0)
	return scale


func energy_ratio() -> float:
	var ceil: float = maxf(1.0, energy_ceiling)
	return clampf(energy / ceil, 0.0, 1.0)


func satiety_ratio() -> float:
	var ceil: float = maxf(1.0, satiety_ceiling)
	return clampf(satiety / ceil, 0.0, 1.0)


func health_ratio() -> float:
	return clampf(health / _health_max(), 0.0, 1.0)


func energy_fill_of_base() -> float:
	return clampf(energy / _base_max(), 0.0, 1.0)


func ceiling_fill_of_base() -> float:
	return clampf(energy_ceiling / _base_max(), 0.0, 1.0)


func satiety_fill_of_base() -> float:
	return clampf(satiety / _base_max(), 0.0, 1.0)


func is_tired() -> bool:
	return energy_ratio() < 0.35


func is_hungry() -> bool:
	return satiety_ratio() < 0.35


func is_frail() -> bool:
	return health < float(_health_cfg().get("frail_below", 35))


func is_critical() -> bool:
	return health < float(_health_cfg().get("slow_below", 20))


func format_status() -> String:
	if not enabled():
		return ""
	var parts: PackedStringArray = PackedStringArray()
	parts.append("健康 %d/%d" % [int(round(health)), int(round(_health_max()))])
	parts.append("精力 %d/%d" % [int(round(energy)), int(round(energy_ceiling))])
	parts.append("饱腹 %d/%d" % [int(round(satiety)), int(round(satiety_ceiling))])
	if nights_without_sleep > 0:
		parts.append("连续未睡%d夜" % nights_without_sleep)
	if days_without_food > 0:
		parts.append("连续未进食%d天" % days_without_food)
	var hint: String = _condition_hint()
	if not hint.is_empty():
		parts.append(hint)
	return "  ".join(parts)


func capture_save() -> Dictionary:
	return {
		"energy": energy,
		"satiety": satiety,
		"energy_ceiling": energy_ceiling,
		"satiety_ceiling": satiety_ceiling,
		"health": health,
		"nights_without_sleep": nights_without_sleep,
		"days_without_food": days_without_food,
		"ate_this_day": ate_this_day,
		"night_sleep_ticks": night_sleep_ticks,
		"last_day_index": last_day_index,
	}


func apply_save(data: Dictionary) -> void:
	if data.is_empty():
		reset()
		return
	var base: float = _base_max()
	energy = float(data.get("energy", base))
	satiety = float(data.get("satiety", base))
	energy_ceiling = float(data.get("energy_ceiling", base))
	satiety_ceiling = float(data.get("satiety_ceiling", base))
	health = float(data.get("health", _health_max()))
	nights_without_sleep = int(data.get("nights_without_sleep", 0))
	days_without_food = int(data.get("days_without_food", 0))
	ate_this_day = bool(data.get("ate_this_day", false))
	night_sleep_ticks = int(data.get("night_sleep_ticks", 0))
	last_day_index = int(data.get("last_day_index", 0))
	_clamp_to_ceilings()


func _tick_sleep(phase: String) -> void:
	var drain: Dictionary = _drain_cfg()
	var restore: float = float(drain.get("energy_sleep_restore", 1.15))
	var night_window: bool = _is_restorative_sleep_phase(phase)
	if not night_window:
		restore *= clampf(float(drain.get("energy_day_sleep_scale", 0.06)), 0.0, 1.0)
	if satiety < float(Config.vitals_cfg().get("hungry_sleep_below", 25)):
		restore *= float(drain.get("energy_hungry_sleep_scale", 0.55))
	if is_frail():
		restore *= clampf(float(_health_cfg().get("frail_sleep_scale", 0.75)), 0.2, 1.0)
	energy = minf(energy_ceiling, energy + restore)
	satiety = maxf(0.0, satiety - float(drain.get("satiety_sleep", 0.18)))
	if night_window:
		night_sleep_ticks += 1


func _tick_awake(phase: String, is_walking: bool) -> void:
	var drain: Dictionary = _drain_cfg()
	var e: float = float(drain.get("energy_idle", 0.28))
	var s: float = float(drain.get("satiety_idle", 0.32))
	if is_walking:
		e += float(drain.get("energy_walk", 0.12))
		s += float(drain.get("satiety_walk", 0.06))
	if Config.time_enabled() and phase == "night":
		e += float(drain.get("energy_night_awake", 0.45))
	var cfg: Dictionary = Config.vitals_cfg()
	if satiety < float(cfg.get("starving_energy_below", 8)):
		e *= maxf(1.0, float(cfg.get("starving_energy_scale", 1.4)))
	elif satiety < float(cfg.get("hungry_energy_below", 25)):
		e *= maxf(1.0, float(cfg.get("hungry_energy_scale", 1.18)))
	if is_frail():
		e *= maxf(1.0, float(_health_cfg().get("frail_drain_scale", 1.25)))
	energy = maxf(0.0, energy - e)
	satiety = maxf(0.0, satiety - s)


func _settle_new_day(day_index: int) -> void:
	var cfg: Dictionary = Config.vitals_cfg()
	var base: float = _base_max()
	var energy_floor: float = float(cfg.get("energy_floor", 40))
	var satiety_floor: float = float(cfg.get("satiety_floor", 35))
	var min_sleep: int = int(cfg.get("min_night_sleep_ticks", 36))
	if night_sleep_ticks >= min_sleep:
		nights_without_sleep = 0
		energy_ceiling = minf(base, energy_ceiling + float(cfg.get("slept_night_energy_recover", 6)))
	else:
		nights_without_sleep += 1
		var pen: float = float(cfg.get("missed_night_energy_penalty", 10))
		pen += float(cfg.get("extra_night_energy_penalty", 4)) * float(nights_without_sleep - 1)
		energy_ceiling = maxf(energy_floor, energy_ceiling - pen)
	if ate_this_day:
		days_without_food = 0
		satiety_ceiling = minf(base, satiety_ceiling + float(cfg.get("ate_day_satiety_recover", 7)))
	else:
		days_without_food += 1
		var s_pen: float = float(cfg.get("missed_day_satiety_penalty", 12))
		s_pen += float(cfg.get("extra_day_satiety_penalty", 5)) * float(days_without_food - 1)
		satiety_ceiling = maxf(satiety_floor, satiety_ceiling - s_pen)
		energy_ceiling = maxf(energy_floor, energy_ceiling - float(cfg.get("missed_day_energy_penalty", 4)))
	_settle_health()
	night_sleep_ticks = 0
	ate_this_day = false
	last_day_index = day_index


func _settle_health() -> void:
	var hcfg: Dictionary = _health_cfg()
	var delta: float = 0.0
	if nights_without_sleep > 0:
		delta -= float(hcfg.get("miss_sleep", 5))
		delta -= float(hcfg.get("extra_sleep", 4)) * float(nights_without_sleep - 1)
	if days_without_food > 0:
		delta -= float(hcfg.get("miss_food", 6))
		delta -= float(hcfg.get("extra_food", 4)) * float(days_without_food - 1)
	if nights_without_sleep > 0 and days_without_food > 0:
		delta -= float(hcfg.get("both_extra", 3))
	if nights_without_sleep == 0 and days_without_food == 0:
		delta += float(hcfg.get("recover_both", 7))
	elif nights_without_sleep == 0 or days_without_food == 0:
		delta += float(hcfg.get("recover_one", 2))
	health = clampf(health + delta, 0.0, _health_max())


func _condition_hint() -> String:
	if is_deceased():
		return "已死亡（不可逆）"
	if is_critical():
		return "病重：走得更慢；黎明健康再降到 0 即死"
	if is_frail():
		return "虚弱：精力掉得更快，睡觉回得更少"
	if health < _health_max() - 0.5:
		return "健康未满：连续缺觉或断食会在黎明继续下降"
	return ""


func _is_restorative_sleep_phase(phase: String) -> bool:
	if not Config.time_enabled():
		return true
	return phase == "dusk" or phase == "night"


func _clamp_to_ceilings() -> void:
	energy_ceiling = clampf(energy_ceiling, 0.0, _base_max())
	satiety_ceiling = clampf(satiety_ceiling, 0.0, _base_max())
	energy = clampf(energy, 0.0, energy_ceiling)
	satiety = clampf(satiety, 0.0, satiety_ceiling)
	health = clampf(health, 0.0, _health_max())


func _base_max() -> float:
	return maxf(1.0, float(Config.vitals_cfg().get("base_max", 100)))


func _health_max() -> float:
	return maxf(1.0, float(_health_cfg().get("max", 100)))


func _health_cfg() -> Dictionary:
	return Config.vitals_health_cfg()


func _drain_cfg() -> Dictionary:
	var raw: Variant = Config.vitals_cfg().get("drain", {})
	return raw if typeof(raw) == TYPE_DICTIONARY else {}
