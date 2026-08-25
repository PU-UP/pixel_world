extends Node2D
class_name FogOfWarLayer
##
## 跟随：未探索=黑；已探索=快照地形（变暗）；当前视野=无遮罩
## 上帝：全图可见；可选标出选中 agent 的当前视野（含 LOS 缺口）
##

const GameWorld = preload("res://scripts/world/world.gd")
const ExplorationMap = preload("res://scripts/world/exploration_map.gd")

var _world: GameWorld = null
var _exploration: ExplorationMap = null
var _god_mode: bool = false
var _focus_center: Vector2i = Vector2i.ZERO
var _focus_radius: int = 0

const COLOR_UNEXPLORED := Color(0.02, 0.02, 0.05, 1.0)
const COLOR_GOD_VISIBLE := Color(1.0, 0.92, 0.42, 0.22)
const COLOR_GOD_BLOCKED := Color(0.08, 0.04, 0.16, 0.42)


func setup(world: GameWorld) -> void:
	_world = world
	z_index = 5
	queue_redraw()


func set_exploration(exploration: ExplorationMap) -> void:
	_exploration = exploration
	queue_redraw()


func set_vision_focus(center: Vector2i, radius: int) -> void:
	_focus_center = center
	_focus_radius = radius
	queue_redraw()


func set_god_mode(on: bool) -> void:
	_god_mode = on
	queue_redraw()


func _draw() -> void:
	if _world == null:
		return
	if _god_mode:
		_draw_god_vision()
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


func _draw_god_vision() -> void:
	if not Config.observer_god_vision_overlay():
		return
	if _exploration == null or _focus_radius <= 0:
		return
	var ts: int = GameWorld.TILE_SIZE
	var r: int = _focus_radius
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy > r * r:
				continue
			var x: int = _focus_center.x + dx
			var y: int = _focus_center.y + dy
			var rect := Rect2(x * ts, y * ts, ts, ts)
			if _exploration.get_state(x, y) == ExplorationMap.TileVis.VISIBLE:
				draw_rect(rect, COLOR_GOD_VISIBLE)
			else:
				draw_rect(rect, COLOR_GOD_BLOCKED)
