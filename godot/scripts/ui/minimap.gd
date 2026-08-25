extends Control
class_name MinimapPanel
##
## 鸟瞰小地图 — 地形缩略 + agent 点位 + 迷雾
##

const GameWorld = preload("res://scripts/world/world.gd")
const PlayerScript = preload("res://scripts/player.gd")
const ExplorationMap = preload("res://scripts/world/exploration_map.gd")

@export var panel_size: Vector2 = Vector2(140, 140)

var _world: GameWorld = null
var _agents: Array = []
var _god_mode: bool = false
var _exploration: ExplorationMap = null
var _expl_rev: int = -1

const COLOR_FOG_UNEXP := Color(0.02, 0.02, 0.05, 0.92)
const COLOR_FOG_EXPLORED := Color(0.12, 0.12, 0.16, 0.72)


func setup(world: GameWorld) -> void:
	_world = world
	custom_minimum_size = panel_size
	size = panel_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func set_agents(agents: Array) -> void:
	_agents = agents
	queue_redraw()


func set_god_mode(on: bool) -> void:
	if on == _god_mode:
		return
	_god_mode = on
	queue_redraw()


func set_exploration(exploration: ExplorationMap) -> void:
	var rev: int = 0
	if exploration != null:
		rev = int(exploration.revision)
	if exploration == _exploration and rev == _expl_rev:
		return
	_exploration = exploration
	_expl_rev = rev
	queue_redraw()


func _draw() -> void:
	if _world == null:
		return
	var w: int = _world.MAP_WIDTH
	var h: int = _world.MAP_HEIGHT
	if w <= 0 or h <= 0:
		return
	var sx: float = panel_size.x / float(w)
	var sy: float = panel_size.y / float(h)
	draw_rect(Rect2(Vector2.ZERO, panel_size), Color(0.02, 0.04, 0.08, 0.85))
	for y in h:
		for x in w:
			var fog_state: int = ExplorationMap.TileVis.VISIBLE
			if not _god_mode and _exploration != null:
				fog_state = _exploration.get_state(x, y)
			if fog_state == ExplorationMap.TileVis.UNEXPLORED:
				draw_rect(Rect2(x * sx, y * sy, maxf(sx, 1.0), maxf(sy, 1.0)), COLOR_FOG_UNEXP)
				continue
			var t: int = _world.tile_at_tile(Vector2i(x, y))
			if fog_state == ExplorationMap.TileVis.EXPLORED and _exploration != null:
				var snap: int = _exploration.snapshot_terrain(x, y)
				if snap >= 0:
					t = snap
			var c: Color = GameWorld.TILE_COLORS.get(t, Color.GRAY)
			if fog_state == ExplorationMap.TileVis.EXPLORED:
				c = c.darkened(0.45)
				if Config.exploration_stale_overlay() and _exploration.is_stale(x, y, _world):
					c = c.lerp(Config.exploration_stale_tint(), 0.55)
			draw_rect(Rect2(x * sx, y * sy, maxf(sx, 1.0), maxf(sy, 1.0)), c)
	if _world.state != null and (_god_mode or _exploration != null):
		for item in _world.state.all_ground_items():
			var it: Vector2i = item.get("tile", Vector2i.ZERO)
			if not _god_mode and _exploration != null and _exploration.get_state(it.x, it.y) != ExplorationMap.TileVis.VISIBLE:
				continue
			var ipx: float = it.x * sx + sx * 0.5
			var ipy: float = it.y * sy + sy * 0.5
			var item_id: String = str(item.get("item_id", ""))
			draw_rect(Rect2(ipx - 1.0, ipy - 1.0, 2.0, 2.0), _item_color(item_id))
	for agent in _agents:
		if agent == null or not is_instance_valid(agent):
			continue
		var p: PlayerScript = agent
		var tile: Vector2i = p.get_tile_position()
		if not _god_mode and _exploration != null and _exploration.get_state(tile.x, tile.y) != ExplorationMap.TileVis.VISIBLE:
			continue
		var px: float = tile.x * sx + sx * 0.5
		var py: float = tile.y * sy + sy * 0.5
		draw_circle(Vector2(px, py), 2.0, Color(1.0, 0.95, 0.2, 0.95))
	draw_rect(Rect2(Vector2.ZERO, panel_size), Color(0.7, 0.75, 0.85, 0.8), false, 1.0)


func _item_color(item_id: String) -> Color:
	var def: Dictionary = Config.world_item_defs().get(item_id, {})
	var rgb: Array = def.get("color", [0.85, 0.75, 0.2])
	if rgb.size() < 3:
		return Color(0.85, 0.75, 0.2)
	return Color(float(rgb[0]), float(rgb[1]), float(rgb[2]), 0.95)
