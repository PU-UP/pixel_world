extends Node2D
class_name FogOfWarLayer
##
## 战争迷雾：未探索=黑；已探索=该格快照地形（变暗）；当前视野=无遮罩
##

const GameWorld = preload("res://scripts/world/world.gd")
const ExplorationMap = preload("res://scripts/world/exploration_map.gd")

var _world: GameWorld = null
var _exploration: ExplorationMap = null
var _god_mode: bool = false

const COLOR_UNEXPLORED := Color(0.02, 0.02, 0.05, 1.0)


func setup(world: GameWorld) -> void:
	_world = world
	z_index = 5
	queue_redraw()


func set_exploration(exploration: ExplorationMap) -> void:
	_exploration = exploration
	queue_redraw()


func set_god_mode(on: bool) -> void:
	_god_mode = on
	queue_redraw()


func _draw() -> void:
	if _world == null or _god_mode:
		return
	if _exploration == null:
		return
	var ts: int = GameWorld.TILE_SIZE
	for y in _world.MAP_HEIGHT:
		for x in _world.MAP_WIDTH:
			var state: int = _exploration.get_state(x, y)
			if state == ExplorationMap.TileVis.VISIBLE:
				continue
			var rect := Rect2(x * ts, y * ts, ts, ts)
			if state == ExplorationMap.TileVis.UNEXPLORED:
				draw_rect(rect, COLOR_UNEXPLORED)
			else:
				var terrain: int = _exploration.snapshot_terrain(x, y)
				if terrain < 0:
					terrain = _world.tile_at_tile(Vector2i(x, y))
				var c: Color = GameWorld.TILE_COLORS.get(terrain, Color(0.2, 0.2, 0.22))
				c = c.darkened(0.4)
				c.a = 1.0
				draw_rect(rect, c)
