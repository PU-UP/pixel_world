class_name ExplorationMap
##
## 每 agent 的探索记忆：未探索(黑) / 已探索快照(灰) / 当前可见(亮)
## 灰色存的是探索当时的地形快照，不是 live 世界。
##

enum TileVis { UNEXPLORED, EXPLORED, VISIBLE }

var _explored: Dictionary = {}  # "x,y" -> {terrain: int, tick: int}
var _visible: Dictionary = {}


func reset(_map_w: int = 0, _map_h: int = 0) -> void:
	_explored.clear()
	_visible.clear()


func update_observer(center: Vector2i, radius: int, world = null, tick: int = 0) -> void:
	_visible.clear()
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy > radius * radius:
				continue
			var tx: int = center.x + dx
			var ty: int = center.y + dy
			var key: String = _key(tx, ty)
			_visible[key] = true
			var terrain: int = 0
			if world != null:
				terrain = int(world.tile_at_tile(Vector2i(tx, ty)))
			_explored[key] = {"terrain": terrain, "tick": tick}


func merge_from(other: ExplorationMap) -> int:
	if other == null:
		return 0
	var added: int = 0
	for key in other._explored.keys():
		var incoming: Dictionary = other._explored[key]
		if not _explored.has(key):
			added += 1
			_explored[key] = incoming.duplicate(true)
			continue
		var mine: Dictionary = _explored[key]
		if int(incoming.get("tick", 0)) > int(mine.get("tick", 0)):
			_explored[key] = incoming.duplicate(true)
	return added


func explored_count() -> int:
	return _explored.size()


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


static func _key(x: int, y: int) -> String:
	return "%d,%d" % [x, y]
