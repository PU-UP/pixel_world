extends Node
class_name WorldState
##
## 权威世界状态 — 地面物品、区域查询
##

signal ground_item_changed()

var _world: GameWorld = null
var _ground: Dictionary = {}  # "x,y" -> {item_id, display_name}
var _pickup_radius: int = 1


func setup(world: GameWorld) -> void:
	_world = world
	_pickup_radius = Config.world_item_pickup_radius()
	_spawn_ground_items()


func reset() -> void:
	_spawn_ground_items()


func region_name_at(tile: Vector2i) -> String:
	return str(region_at(tile).get("name", "荒野"))


func region_id_at(tile: Vector2i) -> String:
	return str(region_at(tile).get("id", ""))


func region_at(tile: Vector2i) -> Dictionary:
	var best_id := ""
	var best_name := ""
	var best_dist: float = INF
	for reg in Config.world_region_defs():
		if typeof(reg) != TYPE_DICTIONARY:
			continue
		var center_arr: Array = reg.get("center", [])
		if center_arr.size() < 2:
			continue
		var center := Vector2i(int(center_arr[0]), int(center_arr[1]))
		var radius: float = float(reg.get("radius", 8))
		var dist: float = float(_manhattan(tile, center))
		if dist <= radius and dist < best_dist:
			best_dist = dist
			best_id = str(reg.get("id", ""))
			best_name = str(reg.get("name", reg.get("id", "")))
	if best_name.is_empty():
		return {"id": "", "name": "荒野"}
	return {"id": best_id, "name": best_name}


func describe_item(item_id: String) -> String:
	var defs: Dictionary = Config.world_item_defs()
	if not defs.has(item_id):
		return "Unknown item."
	var def: Dictionary = defs[item_id]
	return str(def.get("description", def.get("display_name", item_id)))


func find_ground_item_near(agent_tile: Vector2i, item_id: String, radius: int) -> Dictionary:
	for entry in items_near(agent_tile, radius):
		if str(entry.get("item_id", "")) == item_id:
			return entry
	return {}


func items_near(tile: Vector2i, radius: int) -> Array:
	var out: Array = []
	for key in _ground.keys():
		var parts: PackedStringArray = str(key).split(",")
		if parts.size() < 2:
			continue
		var t := Vector2i(int(parts[0]), int(parts[1]))
		if _manhattan(tile, t) <= radius:
			var entry: Dictionary = _ground[key]
			out.append({
				"item_id": str(entry.get("item_id", "")),
				"display_name": str(entry.get("display_name", "")),
				"tile": t,
			})
	return out


func capture_ground() -> Array:
	var out: Array = []
	for item in all_ground_items():
		var tile: Vector2i = item.get("tile", Vector2i.ZERO)
		out.append({
			"item_id": str(item.get("item_id", "")),
			"display_name": str(item.get("display_name", "")),
			"tile": [tile.x, tile.y],
		})
	return out


func restore_ground(items: Array) -> void:
	_ground.clear()
	for raw in items:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = raw
		var tile_arr: Array = item.get("tile", [])
		if tile_arr.size() < 2:
			continue
		var tile := Vector2i(int(tile_arr[0]), int(tile_arr[1]))
		var item_id: String = str(item.get("item_id", "")).strip_edges()
		if item_id.is_empty():
			continue
		if _world != null and not _world.is_walkable_tile(tile):
			continue
		_ground[_tile_key(tile)] = {
			"item_id": item_id,
			"display_name": str(item.get("display_name", item_id)),
		}
	ground_item_changed.emit()


func all_ground_items() -> Array:
	var out: Array = []
	for key in _ground.keys():
		var entry: Dictionary = _ground[key]
		var parts: PackedStringArray = str(key).split(",")
		if parts.size() < 2:
			continue
		out.append({
			"item_id": str(entry.get("item_id", "")),
			"display_name": str(entry.get("display_name", "")),
			"tile": Vector2i(int(parts[0]), int(parts[1])),
		})
	return out


func try_pick_up(agent_tile: Vector2i, item_id: String) -> Dictionary:
	var target_id: String = item_id.strip_edges()
	if target_id.is_empty():
		return {"ok": false, "error": "empty item id"}
	var best_key: String = ""
	var best_dist: int = 9999
	for key in _ground.keys():
		var entry: Dictionary = _ground[key]
		if str(entry.get("item_id", "")) != target_id:
			continue
		var parts: PackedStringArray = str(key).split(",")
		if parts.size() < 2:
			continue
		var t := Vector2i(int(parts[0]), int(parts[1]))
		var dist: int = _manhattan(agent_tile, t)
		if dist <= _pickup_radius and dist < best_dist:
			best_dist = dist
			best_key = str(key)
	if best_key.is_empty():
		return {"ok": false, "error": "item not in range: %s" % target_id}
	var picked: Dictionary = _ground[best_key]
	_ground.erase(best_key)
	ground_item_changed.emit()
	return {
		"ok": true,
		"error": "",
		"item_id": str(picked.get("item_id", "")),
		"display_name": str(picked.get("display_name", "")),
	}


func try_drop(agent_tile: Vector2i, item_id: String) -> Dictionary:
	var target_id: String = item_id.strip_edges()
	if target_id.is_empty():
		return {"ok": false, "error": "empty item id"}
	if _world == null or not _world.is_walkable_tile(agent_tile):
		return {"ok": false, "error": "cannot drop here"}
	var key := _tile_key(agent_tile)
	if _ground.has(key):
		return {"ok": false, "error": "tile occupied"}
	var defs: Dictionary = Config.world_item_defs()
	var def: Dictionary = defs.get(target_id, {})
	_ground[key] = {
		"item_id": target_id,
		"display_name": str(def.get("display_name", target_id)),
	}
	ground_item_changed.emit()
	return {"ok": true, "error": "", "item_id": target_id}


func _spawn_ground_items() -> void:
	_ground.clear()
	var defs: Dictionary = Config.world_item_defs()
	for spawn in Config.world_ground_item_spawns():
		if typeof(spawn) != TYPE_DICTIONARY:
			continue
		var item_id: String = str(spawn.get("item", ""))
		if item_id.is_empty() or not defs.has(item_id):
			continue
		var tile_arr: Array = spawn.get("tile", [])
		if tile_arr.size() < 2:
			continue
		var tile := Vector2i(int(tile_arr[0]), int(tile_arr[1]))
		if _world != null and not _world.is_walkable_tile(tile):
			continue
		var def: Dictionary = defs[item_id]
		_ground[_tile_key(tile)] = {
			"item_id": item_id,
			"display_name": str(def.get("display_name", item_id)),
		}
	ground_item_changed.emit()


func _tile_key(tile: Vector2i) -> String:
	return "%d,%d" % [tile.x, tile.y]


func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)
