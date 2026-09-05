class_name ExplorationMap
##
## 每 agent 的探索记忆：未探索(黑) / 已探索快照(灰) / 当前可见(亮)
## 灰色存的是探索当时的地形快照，不是 live 世界。
##

enum TileVis { UNEXPLORED, EXPLORED, VISIBLE }

var _explored: Dictionary = {}  # "x,y" -> {terrain: int, tick: int}
var _visible: Dictionary = {}
var revision: int = 0


func _bump() -> void:
	revision += 1


func reset(_map_w: int = 0, _map_h: int = 0) -> void:
	_explored.clear()
	_visible.clear()
	_bump()


func update_observer(center: Vector2i, radius: int, world = null, tick: int = 0) -> void:
	_visible.clear()
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy > radius * radius:
				continue
			var tx: int = center.x + dx
			var ty: int = center.y + dy
			var cell := Vector2i(tx, ty)
			if world != null and not world.has_line_of_sight(center, cell):
				continue
			var key: String = _key(tx, ty)
			_visible[key] = true
			var terrain: int = 0
			if world != null:
				terrain = int(world.tile_at_tile(Vector2i(tx, ty)))
			_explored[key] = {"terrain": terrain, "tick": tick}
	_bump()


func merge_from(other: ExplorationMap) -> int:
	if other == null:
		return 0
	var added: int = 0
	var changed: bool = false
	for key in other._explored.keys():
		var incoming: Dictionary = other._explored[key]
		if not _explored.has(key):
			added += 1
			_explored[key] = incoming.duplicate(true)
			changed = true
			continue
		var mine: Dictionary = _explored[key]
		if int(incoming.get("tick", 0)) > int(mine.get("tick", 0)):
			_explored[key] = incoming.duplicate(true)
			changed = true
	if changed:
		_bump()
	return added


func explored_count() -> int:
	return _explored.size()


func visible_count() -> int:
	return _visible.size()


func explored_tiles() -> Array:
	var out: Array = []
	for key in _explored.keys():
		var parts: PackedStringArray = str(key).split(",")
		if parts.size() < 2:
			continue
		out.append(Vector2i(int(parts[0]), int(parts[1])))
	return out


func get_state(x: int, y: int) -> int:
	var key: String = _key(x, y)
	if _visible.has(key):
		return TileVis.VISIBLE
	if _explored.has(key):
		return TileVis.EXPLORED
	return TileVis.UNEXPLORED


func is_explored(x: int, y: int) -> bool:
	return _explored.has(_key(x, y))


func snapshot_terrain(x: int, y: int) -> int:
	var entry: Variant = _explored.get(_key(x, y), null)
	if typeof(entry) != TYPE_DICTIONARY:
		return -1
	return int(entry.get("terrain", -1))


func is_stale(x: int, y: int, world) -> bool:
	if world == null:
		return false
	if get_state(x, y) != TileVis.EXPLORED:
		return false
	var snap: int = snapshot_terrain(x, y)
	if snap < 0:
		return false
	return snap != int(world.tile_at_tile(Vector2i(x, y)))


func stale_tiles(world) -> Array:
	var out: Array = []
	if world == null:
		return out
	for key in _explored.keys():
		var parts: PackedStringArray = str(key).split(",")
		if parts.size() < 2:
			continue
		var x: int = int(parts[0])
		var y: int = int(parts[1])
		if is_stale(x, y, world):
			out.append(Vector2i(x, y))
	return out


func to_dict() -> Dictionary:
	var explored: Dictionary = {}
	for key in _explored.keys():
		var entry: Variant = _explored[key]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		explored[str(key)] = {
			"terrain": int(entry.get("terrain", 0)),
			"tick": int(entry.get("tick", 0)),
		}
	return {"explored": explored}


func from_dict(data: Dictionary) -> void:
	_explored.clear()
	_visible.clear()
	var incoming: Variant = data.get("explored", {})
	if typeof(incoming) != TYPE_DICTIONARY:
		return
	for key in incoming.keys():
		var entry: Variant = incoming[key]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		_explored[str(key)] = {
			"terrain": int(entry.get("terrain", 0)),
			"tick": int(entry.get("tick", 0)),
		}
	_bump()


static func _key(x: int, y: int) -> String:
	return "%d,%d" % [x, y]
