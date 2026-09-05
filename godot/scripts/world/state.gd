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


func bind_clock(clock) -> void:
	if clock == null:
		return
	if clock.tick.is_connected(_on_clock_tick):
		return
	clock.tick.connect(_on_clock_tick)


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


func items_in_sight(agent_tile: Vector2i, radius: int, world) -> Array:
	var out: Array = []
	var r2: int = radius * radius
	for key in _ground.keys():
		var parts: PackedStringArray = str(key).split(",")
		if parts.size() < 2:
			continue
		var t := Vector2i(int(parts[0]), int(parts[1]))
		var dx: int = t.x - agent_tile.x
		var dy: int = t.y - agent_tile.y
		if dx * dx + dy * dy > r2:
			continue
		if world != null and not world.has_line_of_sight(agent_tile, t):
			continue
		var entry: Dictionary = _ground[key]
		out.append({
			"item_id": str(entry.get("item_id", "")),
			"display_name": str(entry.get("display_name", "")),
			"tile": t,
			"key": str(key),
			"dist": abs(dx) + abs(dy),
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


func try_gather_food(agent_tile: Vector2i, item_filter: String, radius: int, world, max_count: int) -> Dictionary:
	if max_count <= 0:
		return {"ok": false, "error": "food inventory full", "items": []}
	var want_all: bool = Config.is_food_gather_token(item_filter)
	var want_id: String = item_filter.strip_edges()
	var cands: Array = items_in_sight(agent_tile, radius, world)
	cands.sort_custom(_sort_food_by_dist)
	var picked: Array = []
	for entry in cands:
		if picked.size() >= max_count:
			break
		var iid: String = str(entry.get("item_id", ""))
		if not Config.item_is_food(iid):
			continue
		if not want_all and iid != want_id:
			continue
		var key: String = str(entry.get("key", ""))
		if key.is_empty() or not _ground.has(key):
			continue
		_ground.erase(key)
		picked.append(iid)
	if picked.is_empty():
		var err: String = "no food in sight" if want_all else "item not in range: %s" % want_id
		return {"ok": false, "error": err, "items": []}
	ground_item_changed.emit()
	return {"ok": true, "error": "", "items": picked}


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
	if _world != null:
		for spawn in _world.orchard_spawns:
			if typeof(spawn) != TYPE_DICTIONARY:
				continue
			var item_id: String = str(spawn.get("item_id", "")).strip_edges()
			if item_id.is_empty() or not defs.has(item_id):
				continue
			var tile: Vector2i = spawn.get("tile", Vector2i(-1, -1))
			if not _world.is_walkable_tile(tile):
				continue
			if _ground.has(_tile_key(tile)):
				continue
			var def: Dictionary = defs[item_id]
			_ground[_tile_key(tile)] = {
				"item_id": item_id,
				"display_name": str(def.get("display_name", item_id)),
			}
	ground_item_changed.emit()


func ground_food_count() -> int:
	var n: int = 0
	for item in all_ground_items():
		if Config.item_is_food(str(item.get("item_id", ""))):
			n += 1
	return n


func _on_clock_tick(tick_index: int) -> void:
	_maybe_spawn_food(tick_index)


func _maybe_spawn_food(tick_index: int) -> void:
	var cfg: Dictionary = Config.world_food_spawn_cfg()
	if cfg.is_empty():
		return
	var interval: int = maxi(1, int(cfg.get("interval_ticks", 72)))
	if tick_index <= 0 or tick_index % interval != 0:
		return
	var max_ground: int = maxi(0, int(cfg.get("max_ground", 12)))
	var per_wave: int = maxi(1, int(cfg.get("per_wave", 2)))
	var attempts: int = maxi(8, int(cfg.get("attempts", 40)))
	var pool: Variant = cfg.get("pool", [])
	if typeof(pool) != TYPE_ARRAY or pool.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = _food_spawn_seed(tick_index)
	var spawned: int = 0
	var fails: int = 0
	while spawned < per_wave and ground_food_count() < max_ground:
		var entry: Dictionary = _pick_food_pool(pool, rng)
		if entry.is_empty():
			break
		var item_id: String = str(entry.get("item", "")).strip_edges()
		if item_id.is_empty() or not Config.item_is_food(item_id):
			fails += 1
			if fails >= per_wave * 3:
				break
			continue
		var terrains: Array = entry.get("terrains", ["grass", "sand"])
		var prefer: String = str(entry.get("prefer", "")).strip_edges()
		var tile: Vector2i = _find_food_tile(terrains, rng, attempts, prefer == "orchard")
		if tile.x < 0:
			fails += 1
			if fails >= per_wave * 3:
				break
			continue
		var def: Dictionary = Config.item_def(item_id)
		_ground[_tile_key(tile)] = {
			"item_id": item_id,
			"display_name": str(def.get("display_name", item_id)),
		}
		spawned += 1
	if spawned > 0:
		ground_item_changed.emit()


func _pick_food_pool(pool: Array, rng: RandomNumberGenerator) -> Dictionary:
	var total: int = 0
	var rows: Array = []
	for raw in pool:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var weight: int = maxi(1, int(raw.get("weight", 1)))
		total += weight
		rows.append({"entry": raw, "weight": weight})
	if total <= 0 or rows.is_empty():
		return {}
	var roll: int = rng.randi_range(1, total)
	var acc: int = 0
	for row in rows:
		acc += int(row["weight"])
		if roll <= acc:
			return row["entry"]
	return rows[-1]["entry"]


func _find_food_tile(terrains: Array, rng: RandomNumberGenerator, attempts: int, prefer_orchard: bool = false) -> Vector2i:
	if _world == null:
		return Vector2i(-1, -1)
	var allowed: Dictionary = {}
	for name in terrains:
		allowed[_terrain_id(str(name))] = true
	var hotspot_chance: float = float(Config.world_food_spawn_cfg().get("hotspot_chance", 0.7))
	if prefer_orchard and rng.randf() < hotspot_chance:
		var tile: Vector2i = _pick_hotspot_tile(allowed, rng)
		if tile.x >= 0:
			return tile
	for _i in attempts:
		var tile := Vector2i(rng.randi_range(0, _world.MAP_WIDTH - 1), rng.randi_range(0, _world.MAP_HEIGHT - 1))
		if _food_tile_ok(tile, allowed):
			return tile
	if prefer_orchard:
		return _pick_hotspot_tile(allowed, rng)
	return Vector2i(-1, -1)


func _pick_hotspot_tile(allowed: Dictionary, rng: RandomNumberGenerator) -> Vector2i:
	if _world == null or _world.food_hotspots.is_empty():
		return Vector2i(-1, -1)
	var spots: Array = _world.food_hotspots.duplicate()
	for _i in spots.size():
		var idx: int = rng.randi_range(0, spots.size() - 1)
		var tile: Vector2i = spots[idx]
		spots.remove_at(idx)
		if _food_tile_ok(tile, allowed):
			return tile
	return Vector2i(-1, -1)


func _food_tile_ok(tile: Vector2i, allowed: Dictionary) -> bool:
	if _world == null or not _world.is_walkable_tile(tile):
		return false
	if not allowed.has(_world.tile_at_tile(tile)):
		return false
	if _ground.has(_tile_key(tile)):
		return false
	return true


func _terrain_id(name: String) -> int:
	match name.strip_edges().to_lower():
		"sand":
			return GameWorld.Tile.SAND
		"water":
			return GameWorld.Tile.WATER
		"tree":
			return GameWorld.Tile.TREE
		"mountain":
			return GameWorld.Tile.MOUNTAIN
		_:
			return GameWorld.Tile.GRASS


func _food_spawn_seed(tick_index: int) -> int:
	var base: int = 1337
	if _world != null and _world.rng != null:
		base = int(_world.rng.seed)
	return base + tick_index * 17


func _tile_key(tile: Vector2i) -> String:
	return "%d,%d" % [tile.x, tile.y]


func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)


func _sort_food_by_dist(a, b) -> bool:
	return int(a.get("dist", 0)) < int(b.get("dist", 0))
