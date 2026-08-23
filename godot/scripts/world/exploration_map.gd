class_name ExplorationMap
##
## 每 agent 的探索记忆：未探索(黑) / 已探索(灰) / 当前可见(亮)
##

enum TileVis { UNEXPLORED, EXPLORED, VISIBLE }

var _explored: Dictionary = {}
var _visible: Dictionary = {}


func reset(_map_w: int = 0, _map_h: int = 0) -> void:
	_explored.clear()
	_visible.clear()


func update_observer(center: Vector2i, radius: int) -> void:
	_visible.clear()
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy > radius * radius:
				continue
			var key: String = _key(center.x + dx, center.y + dy)
			_visible[key] = true
			_explored[key] = true


func merge_from(other: ExplorationMap) -> int:
	if other == null:
		return 0
	var added: int = 0
	for key in other._explored.keys():
		if not _explored.has(key):
			added += 1
		_explored[key] = true
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


static func _key(x: int, y: int) -> String:
	return "%d,%d" % [x, y]
