extends Node
class_name WorldEvents
##
## 世界事件总线 — 周期触发、区域可见
##

signal event_fired(event_id: String, text: String, tick: int)

var _world: GameWorld = null
var _clock: GameClock = null
var _active: Array = []  # {id, text, region_ids, expires_tick}
var _next_fire: Dictionary = {}  # event_id -> tick


func setup(world: GameWorld, clock: GameClock) -> void:
	_world = world
	_clock = clock
	if not _clock.tick.is_connected(_on_tick):
		_clock.tick.connect(_on_tick)
	_init_schedule()


func reset() -> void:
	_active.clear()
	_init_schedule()


func capture_save() -> Dictionary:
	var active: Array = []
	for ev in _active:
		var regions: Array = []
		for r in ev.get("region_ids", []):
			regions.append(str(r))
		active.append({
			"id": str(ev.get("id", "")),
			"text": str(ev.get("text", "")),
			"region_ids": regions,
			"expires_tick": int(ev.get("expires_tick", 0)),
		})
	var next_fire: Dictionary = {}
	for eid in _next_fire.keys():
		next_fire[str(eid)] = int(_next_fire[eid])
	return {"active": active, "next_fire": next_fire}


func restore_save(data: Dictionary) -> void:
	_active.clear()
	_next_fire.clear()
	var incoming_next: Variant = data.get("next_fire", {})
	if typeof(incoming_next) == TYPE_DICTIONARY:
		for eid in incoming_next.keys():
			_next_fire[str(eid)] = int(incoming_next[eid])
	if _next_fire.is_empty():
		_init_schedule()
	else:
		for ev in Config.world_event_defs():
			if typeof(ev) != TYPE_DICTIONARY:
				continue
			var eid: String = str(ev.get("id", ""))
			if eid.is_empty() or _next_fire.has(eid):
				continue
			_next_fire[eid] = int(ev.get("first_tick", 20))
	var incoming_active: Variant = data.get("active", [])
	if typeof(incoming_active) == TYPE_ARRAY:
		for raw in incoming_active:
			if typeof(raw) != TYPE_DICTIONARY:
				continue
			var ev: Dictionary = raw
			var regions: Array = []
			for r in ev.get("region_ids", []):
				regions.append(str(r))
			_active.append({
				"id": str(ev.get("id", "")),
				"text": str(ev.get("text", "")),
				"region_ids": regions,
				"expires_tick": int(ev.get("expires_tick", 0)),
			})
	if _clock != null:
		_prune_expired(_clock.current_tick())


func lines_for_tile(tile: Vector2i) -> PackedStringArray:
	if _world == null or _world.state == null:
		return PackedStringArray()
	var region_id: String = _world.state.region_id_at(tile)
	var lines: PackedStringArray = []
	for ev in _active:
		var regions: Array = ev.get("region_ids", [])
		if regions.is_empty() or region_id in regions:
			lines.append(str(ev.get("text", "")))
	return lines


func _init_schedule() -> void:
	_next_fire.clear()
	for ev in Config.world_event_defs():
		if typeof(ev) != TYPE_DICTIONARY:
			continue
		var eid: String = str(ev.get("id", ""))
		if eid.is_empty():
			continue
		_next_fire[eid] = int(ev.get("first_tick", 20))


func _on_tick(tick: int) -> void:
	_prune_expired(tick)
	for ev in Config.world_event_defs():
		if typeof(ev) != TYPE_DICTIONARY:
			continue
		var eid: String = str(ev.get("id", ""))
		if eid.is_empty():
			continue
		var due: int = int(_next_fire.get(eid, 0))
		if tick < due:
			continue
		var interval: int = int(ev.get("interval_ticks", 80))
		_next_fire[eid] = tick + interval
		var duration: int = int(ev.get("duration_ticks", 12))
		var regions: Array = []
		if ev.has("regions"):
			for r in ev.get("regions", []):
				regions.append(str(r))
		var text: String = str(ev.get("text", ""))
		if text.is_empty():
			continue
		_active.append({
			"id": eid,
			"text": text,
			"region_ids": regions,
			"expires_tick": tick + duration,
		})
		event_fired.emit(eid, text, tick)


func _prune_expired(tick: int) -> void:
	var kept: Array = []
	for ev in _active:
		if int(ev.get("expires_tick", 0)) > tick:
			kept.append(ev)
	_active = kept
