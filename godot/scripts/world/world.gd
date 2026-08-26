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
# 程序化生成:粗略的"椭圆岛屿 + 中心山 + 海岸沙滩 + 边上海水"
# ------------------------------------------------------------------
func _generate_island() -> void:
	tiles.clear()
	var cx := MAP_WIDTH * 0.5
	var cy := MAP_HEIGHT * 0.5
	var rx := MAP_WIDTH * 0.42
	var ry := MAP_HEIGHT * 0.42

	for y in MAP_HEIGHT:
		var row: Array = []
		for x in MAP_WIDTH:
			var nx := (x - cx) / rx
			var ny := (y - cy) / ry
			var d := sqrt(nx * nx + ny * ny)
			var noise := rng.randf_range(-0.06, 0.06)
			var dist := d + noise

			var t: int
			if dist < 0.55:
				t = Tile.GRASS
			elif dist < 0.62:
				t = Tile.GRASS
			elif dist < 0.78:
				# 海岸 + 沙滩混合
				if rng.randf() < 0.6:
					t = Tile.GRASS
				else:
					t = Tile.SAND
			elif dist < 0.85:
				t = Tile.SAND
			else:
				t = Tile.WATER

			# 中心山
			if dist < 0.20 and rng.randf() < 0.35:
				t = Tile.MOUNTAIN
			# 散落树
			elif t == Tile.GRASS and rng.randf() < 0.08:
				t = Tile.TREE
			# 边界强制海水,封口
			if x == 0 or y == 0 or x == MAP_WIDTH - 1 or y == MAP_HEIGHT - 1:
				t = Tile.WATER
			row.append(t)
		tiles.append(row)

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
