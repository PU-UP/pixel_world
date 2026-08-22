extends Node2D
class_name GameWorld
##
## 荒岛世界（程序化生成的占位地形，P1 阶段先验证渲染与相机）
## 真实 TileMap + 美术资源留到 P7 替换。
##

const TILE_SIZE: int = 16
const WorldStateScript = preload("res://scripts/world/state.gd")
const WorldEventsScript = preload("res://scripts/world/events.gd")
var MAP_WIDTH: int = 64   # 瓦片 — 启动时从 config 覆盖
var MAP_HEIGHT: int = 64  # 瓦片

# 地形调色板（占位色 — P7 替换为 tileset）
enum Tile { GRASS = 0, SAND = 1, WATER = 2, TREE = 3, MOUNTAIN = 4 }
const TILE_COLORS := {
	Tile.GRASS: Color(0.45, 0.72, 0.32),
	Tile.SAND: Color(0.95, 0.84, 0.55),
	Tile.WATER: Color(0.22, 0.49, 0.74),
	Tile.TREE: Color(0.11, 0.30, 0.14),
	Tile.MOUNTAIN: Color(0.45, 0.45, 0.48),
}

var tiles: Array = []   # 二维 [y][x] -> Tile
var state: WorldStateScript = null
var events: WorldEventsScript = null
var rng: RandomNumberGenerator

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
	if x < 0 or y < 0 or x >= MAP_WIDTH or y >= MAP_HEIGHT:
		return Tile.WATER
	return tiles[y][x]

func is_walkable(world_pos: Vector2) -> bool:
	var t := tile_at(world_pos)
	return t == Tile.GRASS or t == Tile.SAND

# P2: 瓦片坐标版, 给 A* 寻路用, 避免重复 floor/除法
func is_walkable_tile(tile: Vector2i) -> bool:
	if tile.x < 0 or tile.y < 0 or tile.x >= MAP_WIDTH or tile.y >= MAP_HEIGHT:
		return false
	var t: int = tiles[tile.y][tile.x]
	return t == Tile.GRASS or t == Tile.SAND

func tile_at_tile(tile: Vector2i) -> int:
	if tile.x < 0 or tile.y < 0 or tile.x >= MAP_WIDTH or tile.y >= MAP_HEIGHT:
		return Tile.WATER
	return tiles[tile.y][tile.x]

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
func _draw() -> void:
	for y in MAP_HEIGHT:
		for x in MAP_WIDTH:
			var rect := Rect2(x * TILE_SIZE, y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
			draw_rect(rect, TILE_COLORS[tiles[y][x]])
	_draw_ground_items()


func _draw_ground_items() -> void:
	if state == null:
		return
	var defs: Dictionary = Config.world_item_defs()
	for entry in state.all_ground_items():
		var tile: Vector2i = entry.get("tile", Vector2i.ZERO)
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
