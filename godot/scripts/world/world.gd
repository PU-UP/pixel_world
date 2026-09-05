extends Node2D
class_name GameWorld
##
## 荒岛世界（程序化生成 + 16×16 像素 TileMapLayer）
##

const TILE_SIZE: int = 16
const WorldStateScript = preload("res://scripts/world/state.gd")
const WorldEventsScript = preload("res://scripts/world/events.gd")
const ExplorationMap = preload("res://scripts/world/exploration_map.gd")
const PixelTileset = preload("res://scripts/world/pixel_tileset.gd")
var MAP_WIDTH: int = 64   # 瓦片 — 启动时从 config 覆盖
var MAP_HEIGHT: int = 64  # 瓦片

enum Tile { GRASS = 0, SAND = 1, WATER = 2, TREE = 3, MOUNTAIN = 4 }
const TILE_COLORS := {
	Tile.GRASS: Color(0.45, 0.72, 0.32),
	Tile.SAND: Color(0.95, 0.84, 0.55),
	Tile.WATER: Color(0.22, 0.49, 0.74),
	Tile.TREE: Color(0.11, 0.30, 0.14),
	Tile.MOUNTAIN: Color(0.45, 0.45, 0.48),
}

var tiles: Array = []   # 二维 [y][x] -> Tile
var _tile_overrides: Dictionary = {}  # "x,y" -> Tile
var _exploration_maps: Array = []
var state: WorldStateScript = null
var events: WorldEventsScript = null
var rng: RandomNumberGenerator
var _item_filter = null
var _god_items: bool = true
var _filter_rev: int = -1
var tile_revision: int = 0
var _los_block_ids_cache: Dictionary = {}
var _terrain_map: TileMapLayer = null
var food_hotspots: Array = []
var orchard_spawns: Array = []

func _ready() -> void:
	rng = RandomNumberGenerator.new()
	var cfg := Config.world_cfg
	if cfg.size() > 0:
		MAP_WIDTH = int(cfg.get("map_width", MAP_WIDTH))
		MAP_HEIGHT = int(cfg.get("map_height", MAP_HEIGHT))
		rng.seed = int(cfg.get("seed", 1337))
	else:
		rng.seed = 1337
	_generate_island()
	_ensure_terrain_map()
	state = WorldStateScript.new()
	state.name = "WorldState"
	add_child(state)
	state.setup(self)
	state.ground_item_changed.connect(_on_ground_items_changed)
	events = WorldEventsScript.new()
	events.name = "WorldEvents"
	add_child(events)
	queue_redraw()


func _on_ground_items_changed() -> void:
	queue_redraw()

func world_size() -> Vector2:
	return Vector2(MAP_WIDTH * TILE_SIZE, MAP_HEIGHT * TILE_SIZE)

func tile_at(world_pos: Vector2) -> int:
	var x := int(floor(world_pos.x / TILE_SIZE))
	var y := int(floor(world_pos.y / TILE_SIZE))
	return tile_at_tile(Vector2i(x, y))

func is_walkable(world_pos: Vector2) -> bool:
	var t := tile_at(world_pos)
	return t == Tile.GRASS or t == Tile.SAND

# P2: 瓦片坐标版, 给 A* 寻路用, 避免重复 floor/除法
func is_walkable_tile(tile: Vector2i) -> bool:
	if tile.x < 0 or tile.y < 0 or tile.x >= MAP_WIDTH or tile.y >= MAP_HEIGHT:
		return false
	var t: int = tile_at_tile(tile)
	return t == Tile.GRASS or t == Tile.SAND


func set_view_filter(exploration, god_mode: bool) -> void:
	var rev: int = 0
	if exploration != null:
		rev = int(exploration.revision)
	if exploration == _item_filter and god_mode == _god_items and rev == _filter_rev:
		return
	_item_filter = exploration
	_god_items = god_mode
	_filter_rev = rev
	queue_redraw()

func tile_at_tile(tile: Vector2i) -> int:
	if tile.x < 0 or tile.y < 0 or tile.x >= MAP_WIDTH or tile.y >= MAP_HEIGHT:
		return Tile.WATER
	var key: String = _tile_key(tile)
	if _tile_overrides.has(key):
		return int(_tile_overrides[key])
	return tiles[tile.y][tile.x]


func set_tile(tile: Vector2i, terrain: int, redraw: bool = true) -> bool:
	if tile.x < 0 or tile.y < 0 or tile.x >= MAP_WIDTH or tile.y >= MAP_HEIGHT:
		return false
	if terrain < Tile.GRASS or terrain > Tile.MOUNTAIN:
		return false
	if tile_at_tile(tile) == terrain:
		return false
	_tile_overrides[_tile_key(tile)] = terrain
	tile_revision += 1
	_set_terrain_cell(tile, terrain)
	if redraw:
		queue_redraw()
	return true


func reset_tile_overrides() -> void:
	_tile_overrides.clear()
	_exploration_maps.clear()
	tile_revision += 1
	_sync_terrain_map()
	queue_redraw()


func capture_tile_overrides() -> Dictionary:
	var out: Dictionary = {}
	for key in _tile_overrides.keys():
		out[str(key)] = int(_tile_overrides[key])
	return out


func restore_tile_overrides(data: Dictionary) -> void:
	_tile_overrides.clear()
	for key in data.keys():
		_tile_overrides[str(key)] = int(data[key])
	tile_revision += 1
	_sync_terrain_map()
	queue_redraw()


func apply_region_tile_change(region_ids: Array, from_id: int, to_id: int, count: int) -> Array:
	var changed: Array = []
	if count <= 0 or from_id < 0 or to_id < 0:
		return changed
	var filter: Dictionary = {}
	for rid in region_ids:
		var s: String = str(rid)
		if not s.is_empty():
			filter[s] = true
	var origin: Vector2i = _region_center(region_ids)
	var candidates: Array = []
	for y in MAP_HEIGHT:
		for x in MAP_WIDTH:
			var cell := Vector2i(x, y)
			if tile_at_tile(cell) != from_id:
				continue
			if not filter.is_empty():
				var rid: String = state.region_id_at(cell) if state != null else ""
				if not filter.has(rid):
					continue
			var remembered: int = 1
			if _any_snapshot_is(cell, from_id):
				remembered = 0
			var dist: int = absi(cell.x - origin.x) + absi(cell.y - origin.y)
			candidates.append({"tile": cell, "remembered": remembered, "dist": dist})
	candidates.sort_custom(func(a, b):
		if int(a["remembered"]) != int(b["remembered"]):
			return int(a["remembered"]) < int(b["remembered"])
		return int(a["dist"]) < int(b["dist"])
	)
	for row in candidates:
		if changed.size() >= count:
			break
		var cell: Vector2i = row["tile"]
		if set_tile(cell, to_id, false):
			changed.append(cell)
	if changed.size() > 0:
		queue_redraw()
	return changed


func register_exploration(exploration) -> void:
	if exploration == null:
		return
	if exploration in _exploration_maps:
		return
	_exploration_maps.append(exploration)


func unregister_exploration(exploration) -> void:
	_exploration_maps.erase(exploration)


func _any_snapshot_is(tile: Vector2i, terrain: int) -> bool:
	for exploration in _exploration_maps:
		if exploration == null:
			continue
		if int(exploration.snapshot_terrain(tile.x, tile.y)) == terrain:
			return true
	return false


func _region_center(region_ids: Array) -> Vector2i:
	var want: String = ""
	for rid in region_ids:
		if not str(rid).is_empty():
			want = str(rid)
			break
	if want.is_empty():
		return Vector2i(int(MAP_WIDTH * 0.5), int(MAP_HEIGHT * 0.5))
	for reg in Config.world_region_defs():
		if typeof(reg) != TYPE_DICTIONARY:
			continue
		if str(reg.get("id", "")) != want:
			continue
		var c: Array = reg.get("center", [])
		if c.size() >= 2:
			return Vector2i(int(c[0]), int(c[1]))
	return Vector2i(int(MAP_WIDTH * 0.5), int(MAP_HEIGHT * 0.5))


func terrain_id_from_name(name: String) -> int:
	return _tile_id_from_name(name)


static func _tile_key(tile: Vector2i) -> String:
	return "%d,%d" % [tile.x, tile.y]


func blocks_sight(tile: Vector2i) -> bool:
	return _los_block_ids().has(tile_at_tile(tile))


func has_line_of_sight(from: Vector2i, to: Vector2i) -> bool:
	if not Config.perception_los_enabled():
		return true
	if from == to:
		return true
	var cells: Array = _trace_line(from, to)
	for i in range(cells.size() - 1):
		var cell: Vector2i = cells[i]
		if cell == from:
			continue
		if blocks_sight(cell):
			return false
	return true


func _los_block_ids() -> Dictionary:
	if not _los_block_ids_cache.is_empty():
		return _los_block_ids_cache
	for raw in Config.perception_los_block_names():
		var tid: int = _tile_id_from_name(str(raw))
		if tid >= 0:
			_los_block_ids_cache[tid] = true
	return _los_block_ids_cache


func _tile_id_from_name(name: String) -> int:
	match name.strip_edges().to_lower():
		"grass":
			return Tile.GRASS
		"sand":
			return Tile.SAND
		"water":
			return Tile.WATER
		"tree":
			return Tile.TREE
		"mountain":
			return Tile.MOUNTAIN
		_:
			return -1


func _trace_line(a: Vector2i, b: Vector2i) -> Array:
	var cells: Array = [a]
	var x: int = a.x
	var y: int = a.y
	var dx: int = absi(b.x - a.x)
	var dy: int = absi(b.y - a.y)
	var sx: int = 1 if a.x < b.x else -1
	var sy: int = 1 if a.y < b.y else -1
	var err: int = dx - dy
	while x != b.x or y != b.y:
		var e2: int = err * 2
		if e2 > -dy:
			err -= dy
			x += sx
		if e2 < dx:
			err += dx
			y += sy
		cells.append(Vector2i(x, y))
	return cells

# ------------------------------------------------------------------
# 程序化生成: 不规则海岸 + 山脊/林带 + 果园空地
# ------------------------------------------------------------------
func _generate_island() -> void:
	food_hotspots.clear()
	orchard_spawns.clear()
	var gen: Dictionary = Config.world_generation_cfg()
	_fill_base_land(gen)
	_carve_bays(gen)
	_stamp_mountains(gen)
	_stamp_scatter_trees(gen)
	_stamp_groves(gen)
	_stamp_orchards(gen)
	_protect_spawns(int(gen.get("spawn_clear_radius", 5)))
	_seal_border()


func _fill_base_land(gen: Dictionary) -> void:
	tiles.clear()
	var cx := MAP_WIDTH * 0.5
	var cy := MAP_HEIGHT * 0.5
	var rx := MAP_WIDTH * 0.42
	var ry := MAP_HEIGHT * 0.42
	var coast_noise: float = float(gen.get("coast_noise", 0.06))
	var coast_wobble: float = float(gen.get("coast_wobble", 0.0))
	var inner_grass: float = float(gen.get("inner_grass", 0.62))
	var sand_start: float = float(gen.get("sand_start", 0.78))
	var sand_end: float = float(gen.get("sand_end", 0.85))
	for y in MAP_HEIGHT:
		var row: Array = []
		for x in MAP_WIDTH:
			var nx := (x - cx) / rx
			var ny := (y - cy) / ry
			var d := sqrt(nx * nx + ny * ny)
			var ang := atan2(ny, nx)
			var dist := d + rng.randf_range(-coast_noise, coast_noise) + coast_wobble * sin(ang * 3.0)
			var t: int
			if dist < inner_grass:
				t = Tile.GRASS
			elif dist < sand_start:
				t = Tile.GRASS if rng.randf() < 0.55 else Tile.SAND
			elif dist < sand_end:
				t = Tile.SAND
			else:
				t = Tile.WATER
			row.append(t)
		tiles.append(row)


func _carve_bays(gen: Dictionary) -> void:
	var bays: Variant = gen.get("bays", [])
	if typeof(bays) != TYPE_ARRAY:
		return
	for raw in bays:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var center := _center_of(raw)
		var radius: float = float(raw.get("radius", 8))
		_stamp_disk(center, radius, Tile.WATER, 1.0)


func _stamp_mountains(gen: Dictionary) -> void:
	var cx := MAP_WIDTH * 0.5
	var cy := MAP_HEIGHT * 0.5
	var rx := MAP_WIDTH * 0.42
	var ry := MAP_HEIGHT * 0.42
	var core: float = float(gen.get("mountain_core", 0.20))
	var core_chance: float = float(gen.get("mountain_core_chance", 0.35))
	for y in MAP_HEIGHT:
		for x in MAP_WIDTH:
			var nx := (x - cx) / rx
			var ny := (y - cy) / ry
			var d := sqrt(nx * nx + ny * ny)
			if d < core and _is_land(Vector2i(x, y)) and rng.randf() < core_chance:
				tiles[y][x] = Tile.MOUNTAIN
	var ridges: Variant = gen.get("ridges", [])
	if typeof(ridges) != TYPE_ARRAY:
		return
	for raw in ridges:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var center := _center_of(raw)
		var radius: float = float(raw.get("radius", 6))
		var chance: float = float(raw.get("chance", 0.45))
		_stamp_disk(center, radius, Tile.MOUNTAIN, chance, true)


func _stamp_scatter_trees(gen: Dictionary) -> void:
	var chance: float = float(gen.get("tree_scatter", 0.08))
	for y in MAP_HEIGHT:
		for x in MAP_WIDTH:
			if tiles[y][x] == Tile.GRASS and rng.randf() < chance:
				tiles[y][x] = Tile.TREE


func _stamp_groves(gen: Dictionary) -> void:
	var groves: Variant = gen.get("groves", [])
	if typeof(groves) != TYPE_ARRAY:
		return
	for raw in groves:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var center := _center_of(raw)
		var radius: float = float(raw.get("radius", 8))
		var chance: float = float(raw.get("tree_chance", 0.5))
		_stamp_disk(center, radius, Tile.TREE, chance, true)


func _stamp_orchards(gen: Dictionary) -> void:
	var orchards: Variant = gen.get("orchards", [])
	if typeof(orchards) != TYPE_ARRAY:
		return
	for raw in orchards:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var center := _center_of(raw)
		var radius: float = maxf(2.0, float(raw.get("radius", 5)))
		var ring: float = maxf(1.0, float(raw.get("ring", 2)))
		var r2: float = radius + ring
		for y in range(center.y - int(ceil(r2)), center.y + int(ceil(r2)) + 1):
			for x in range(center.x - int(ceil(r2)), center.x + int(ceil(r2)) + 1):
				var tile := Vector2i(x, y)
				if not _in_bounds(tile):
					continue
				var d := Vector2(x - center.x, y - center.y).length()
				if d <= radius:
					if tiles[y][x] != Tile.WATER:
						tiles[y][x] = Tile.GRASS
					if d <= radius - 0.5 and tiles[y][x] == Tile.GRASS:
						food_hotspots.append(tile)
				elif d <= r2 and tiles[y][x] == Tile.GRASS:
					tiles[y][x] = Tile.TREE
		_seed_orchard_food(raw, center, radius)


func _seed_orchard_food(raw: Dictionary, center: Vector2i, radius: float) -> void:
	var foods: Variant = raw.get("food", [])
	if typeof(foods) != TYPE_ARRAY:
		return
	var candidates: Array = []
	for spot in food_hotspots:
		var tile: Vector2i = spot
		if Vector2(tile.x - center.x, tile.y - center.y).length() <= radius:
			candidates.append(tile)
	for i in candidates.size():
		var j: int = rng.randi_range(i, candidates.size() - 1)
		var tmp: Vector2i = candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = tmp
	var placed: int = 0
	for item_raw in foods:
		if placed >= candidates.size():
			break
		var item_id: String = str(item_raw).strip_edges()
		if item_id.is_empty() or not Config.item_is_food(item_id):
			continue
		var tile: Vector2i = candidates[placed]
		placed += 1
		orchard_spawns.append({"item_id": item_id, "tile": tile})


func _protect_spawns(clear_radius: int) -> void:
	for cfg in Config.all_agents():
		if typeof(cfg) != TYPE_DICTIONARY:
			continue
		var spawn: Array = cfg.get("spawn_tile", [])
		if spawn.size() < 2:
			continue
		var origin := Vector2i(int(spawn[0]), int(spawn[1]))
		for y in range(origin.y - clear_radius, origin.y + clear_radius + 1):
			for x in range(origin.x - clear_radius, origin.x + clear_radius + 1):
				var tile := Vector2i(x, y)
				if not _in_bounds(tile):
					continue
				if absi(x - origin.x) + absi(y - origin.y) > clear_radius:
					continue
				if tiles[y][x] == Tile.TREE or tiles[y][x] == Tile.MOUNTAIN:
					tiles[y][x] = Tile.GRASS


func _seal_border() -> void:
	for y in MAP_HEIGHT:
		tiles[y][0] = Tile.WATER
		tiles[y][MAP_WIDTH - 1] = Tile.WATER
	for x in MAP_WIDTH:
		tiles[0][x] = Tile.WATER
		tiles[MAP_HEIGHT - 1][x] = Tile.WATER


func _stamp_disk(center: Vector2i, radius: float, terrain: int, chance: float, land_only: bool = false) -> void:
	var r: int = int(ceil(radius))
	for y in range(center.y - r, center.y + r + 1):
		for x in range(center.x - r, center.x + r + 1):
			var tile := Vector2i(x, y)
			if not _in_bounds(tile):
				continue
			if Vector2(x - center.x, y - center.y).length() > radius:
				continue
			if land_only and not _is_land(tile):
				continue
			if chance < 1.0 and rng.randf() >= chance:
				continue
			tiles[y][x] = terrain


func _center_of(raw: Dictionary) -> Vector2i:
	var arr: Array = raw.get("center", [])
	if arr.size() < 2:
		return Vector2i(int(MAP_WIDTH * 0.5), int(MAP_HEIGHT * 0.5))
	return Vector2i(int(arr[0]), int(arr[1]))


func _is_land(tile: Vector2i) -> bool:
	if not _in_bounds(tile):
		return false
	var t: int = tiles[tile.y][tile.x]
	return t == Tile.GRASS or t == Tile.SAND or t == Tile.TREE or t == Tile.MOUNTAIN


func _in_bounds(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.y >= 0 and tile.x < MAP_WIDTH and tile.y < MAP_HEIGHT

# ------------------------------------------------------------------
# 渲染
# ------------------------------------------------------------------
func _ensure_terrain_map() -> void:
	if _terrain_map == null:
		_terrain_map = TileMapLayer.new()
		_terrain_map.name = "Terrain"
		_terrain_map.z_index = -1
		_terrain_map.tile_set = PixelTileset.tile_set()
		add_child(_terrain_map)
	_sync_terrain_map()


func _sync_terrain_map() -> void:
	if _terrain_map == null:
		return
	for y in MAP_HEIGHT:
		for x in MAP_WIDTH:
			_set_terrain_cell(Vector2i(x, y), tile_at_tile(Vector2i(x, y)))


func _set_terrain_cell(tile: Vector2i, terrain: int) -> void:
	if _terrain_map == null:
		return
	_terrain_map.set_cell(tile, 0, PixelTileset.atlas_coords(terrain))


func _draw() -> void:
	_draw_ground_items()


func _draw_ground_items() -> void:
	if state == null:
		return
	var defs: Dictionary = Config.world_item_defs()
	for entry in state.all_ground_items():
		var tile: Vector2i = entry.get("tile", Vector2i.ZERO)
		if not _god_items and _item_filter != null:
			if _item_filter.get_state(tile.x, tile.y) != ExplorationMap.TileVis.VISIBLE:
				continue
		var item_id: String = str(entry.get("item_id", ""))
		var color := Color(0.95, 0.85, 0.25)
		if defs.has(item_id):
			var def: Dictionary = defs[item_id]
			if def.has("color") and typeof(def["color"]) == TYPE_ARRAY:
				var c: Array = def["color"]
				if c.size() >= 3:
					color = Color(float(c[0]), float(c[1]), float(c[2]))
		var center := Vector2(
			tile.x * TILE_SIZE + TILE_SIZE * 0.5,
			tile.y * TILE_SIZE + TILE_SIZE * 0.5,
		)
		draw_circle(center, 3.0, color)
		draw_circle(center, 3.0, Color(0, 0, 0, 0.5), false, 1.0)
