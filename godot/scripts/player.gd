extends CharacterBody2D
class_name Player
##
## P1: WASD 自由移动 + 阻挡
## P1.5: 视野感知 + 行动日志 + 观测接口
## P2: 统一走 action 队列 — WASD/鼠标点击都生成 MOVE_TO, A* 寻路执行
##     状态机: IDLE → WALKING(沿 _path) → pop 下一 action → WALKING ...
##

const GameWorld = preload("res://scripts/world/world.gd")
const GameClock = preload("res://scripts/world/clock.gd")
const AStarPathfinder = preload("res://scripts/world/pathfinding.gd")
const AgentActions = preload("res://scripts/agent/actions.gd")

const TILE_SIZE: int = GameWorld.TILE_SIZE

@export var move_speed_px: float = 80.0
@export var body_color: Color = Color(0.78, 0.23, 0.23)
@export var face_color: Color = Color(0.95, 0.78, 0.61)
@export var agent_id: StringName = &"player"
@export var display_name: String = "Player"
@export var observation_radius_tiles: int = 6
@export var observation_refresh_ticks: int = 2
@export var action_log_max: int = 8
@export var move_log_threshold_px: float = 1.0
@export var debug_show_path: bool = true   # P2 调试: 画路径

# ---- 状态 ----
var _world = null       # GameWorld
var _clock = null       # GameClock
var _last_dir: Vector2 = Vector2.DOWN
var _last_position: Vector2 = Vector2.ZERO
var _last_observation_tick: int = -1
var _observation_text: String = "(no observation yet)"
var action_log: Array = []

# ---- P2 状态机 ----
enum State { IDLE, WALKING }
var _state: int = State.IDLE
var _action_queue: Array = []           # 待执行的 actions
var _current_action: Dictionary = {}    # 正在执行的
var _current_path: Array = []           # 像素路径 (Vector2)
var _path_idx: int = 0                  # 下一个要走的路径点索引

# ---- Debug draw ----
var _debug_path: PackedVector2Array = PackedVector2Array()
var _pending_spawn: Variant = null

# ------------------------------------------------------------------
# 生命周期
# ------------------------------------------------------------------
func is_busy() -> bool:
	return _state == State.WALKING


func get_tile_position() -> Vector2i:
	return Vector2i(
		int(floor(global_position.x / TILE_SIZE)),
		int(floor(global_position.y / TILE_SIZE))
	)


func apply_agent_config(cfg: Dictionary) -> void:
	if cfg.is_empty():
		return
	if cfg.has("id"):
		agent_id = StringName(str(cfg["id"]))
	if cfg.has("display_name"):
		display_name = str(cfg["display_name"])
	if cfg.has("spawn_tile"):
		_pending_spawn = cfg["spawn_tile"]


func _relocate_spawn() -> void:
	var tile := Vector2i(32, 32)
	if _pending_spawn != null and typeof(_pending_spawn) == TYPE_ARRAY and _pending_spawn.size() >= 2:
		tile = Vector2i(int(_pending_spawn[0]), int(_pending_spawn[1]))
	if _world != null and not _world.is_walkable_tile(tile):
		tile = _find_nearest_walkable_tile(tile)
	global_position = Vector2(tile.x * TILE_SIZE + TILE_SIZE * 0.5, tile.y * TILE_SIZE + TILE_SIZE * 0.5)
	_last_position = global_position


func _apply_runtime_config() -> void:
	var agent_cfg: Dictionary = Config.runtime.get("agent", {})
	observation_radius_tiles = int(agent_cfg.get("perception_radius", observation_radius_tiles))
	observation_refresh_ticks = int(agent_cfg.get("observation_refresh_ticks", observation_refresh_ticks))
	action_log_max = int(agent_cfg.get("action_log_max", action_log_max))
	move_speed_px = float(agent_cfg.get("move_speed_px", move_speed_px))


func _ready() -> void:
	_apply_runtime_config()
	apply_agent_config(Config.agent_config())
	var img := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(body_color)
	for px in 4:
		for py in 3:
			img.set_pixel(6 + px, 2 + py, face_color)
	img.set_pixel(0, 0, Color.BLACK)
	img.set_pixel(TILE_SIZE - 1, 0, Color.BLACK)
	img.set_pixel(0, TILE_SIZE - 1, Color.BLACK)
	img.set_pixel(TILE_SIZE - 1, TILE_SIZE - 1, Color.BLACK)
	for i in range(1, TILE_SIZE - 1):
		img.set_pixel(i, 0, Color.BLACK)
		img.set_pixel(i, TILE_SIZE - 1, Color.BLACK)
		img.set_pixel(0, i, Color.BLACK)
		img.set_pixel(TILE_SIZE - 1, i, Color.BLACK)
	var tex := ImageTexture.create_from_image(img)
	$Sprite2D.texture = tex
	_last_position = global_position

func bind_world(world) -> void:
	_world = world
	if is_inside_tree():
		_relocate_spawn()

func bind_clock(clock) -> void:
	_clock = clock

# ------------------------------------------------------------------
# 公开接口 — 外部(LLM / 鼠标 / 键盘)灌入 action
# ------------------------------------------------------------------
func enqueue_action(action: Dictionary) -> void:
	var v: Dictionary = AgentActions.validate(action)
	if not v["ok"]:
		_log_action(_clock.current_tick() if _clock else -1, "reject", "invalid: %s" % v["error"])
		printerr("[Player] reject action: ", v["error"], " action=", action)
		return
	# 已实现校验
	if action["kind"] not in AgentActions.IMPLEMENTED_KINDS:
		_log_action(_clock.current_tick() if _clock else -1, "reject", "unimplemented: %s" % action["kind"])
		printerr("[Player] kind not implemented in P2: ", action["kind"])
		return
	_action_queue.append(action)
	_log_action(_clock.current_tick() if _clock else -1, "enqueue", AgentActions.format_action(action))
	if _state == State.IDLE:
		_pump_next_action()

## 便捷: 像素坐标 -> MOVE_TO
func enqueue_move_to_world(world_pos: Vector2) -> void:
	var t := Vector2i(int(floor(world_pos.x / TILE_SIZE)), int(floor(world_pos.y / TILE_SIZE)))
	enqueue_move_to_tile(t)

## 便捷: 瓦片坐标 -> MOVE_TO
func enqueue_move_to_tile(tile: Vector2i) -> void:
	enqueue_action(AgentActions.make_move_to(tile.x, tile.y))

func clear_action_queue() -> void:
	_action_queue.clear()
	_current_path = []
	_path_idx = 0
	_state = State.IDLE
	_current_action = {}

# ------------------------------------------------------------------
# 主循环
# ------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	match _state:
		State.WALKING:
			_advance_along_path(delta)
		State.IDLE:
			# 等待下一 action; _unhandled_input 已在触发 enqueue
			pass

	# 世界边界 clamp (防止寻路把玩家带到角外)
	var half: float = TILE_SIZE * 0.5
	var size: Vector2 = (_world.world_size() if _world != null else Vector2(1024, 1024))
	global_position.x = clamp(global_position.x, half, size.x - half)
	global_position.y = clamp(global_position.y, half, size.y - half)

	# ---- P1.5 观测/日志 hook ----
	_refresh_observation_if_needed()
	_maybe_log_position_change()

	queue_redraw()  # debug 画路径

func _draw() -> void:
	if not debug_show_path:
		return
	if _current_path.is_empty():
		return
	# 当前路径: 黄点串
	for i in range(_path_idx, _current_path.size()):
		var p: Vector2 = _current_path[i] - global_position
		var c := Color(1.0, 0.9, 0.2, 0.5) if i == _path_idx else Color(1.0, 0.9, 0.2, 0.25)
		draw_circle(p, 3.0, c)
	# 目标点: 红色 X
	var goal: Vector2 = _current_path[-1] - global_position
	draw_line(goal + Vector2(-4, -4), goal + Vector2(4, 4), Color(1, 0.3, 0.3, 0.8), 1.5)
	draw_line(goal + Vector2(-4, 4), goal + Vector2(4, -4), Color(1, 0.3, 0.3, 0.8), 1.5)

# ------------------------------------------------------------------
# 状态机: IDLE -> WALKING
# ------------------------------------------------------------------
func _pump_next_action() -> void:
	if _action_queue.is_empty():
		_state = State.IDLE
		_current_action = {}
		return
	_current_action = _action_queue.pop_front()
	match _current_action["kind"]:
		AgentActions.KIND_MOVE_TO:
			_start_move_to(_current_action["params"]["x"], _current_action["params"]["y"])
		_:
			# 未知 kind(不应到这,validate 已过滤)
			_state = State.IDLE
			_current_action = {}

func _start_move_to(gx: int, gy: int) -> void:
	var start_tile := Vector2i(int(floor(global_position.x / TILE_SIZE)), int(floor(global_position.y / TILE_SIZE)))
	var goal_tile := Vector2i(gx, gy)
	if start_tile == goal_tile:
		# 已经在, 直接完成
		_log_action(_clock.current_tick() if _clock else -1, "move", "already at (%d, %d)" % [gx, gy])
		_pump_next_action()
		return
	var path: Array = AStarPathfinder.find_path(_world, start_tile, goal_tile)
	if path.is_empty():
		_log_action(_clock.current_tick() if _clock else -1, "move", "UNREACHABLE (%d, %d)" % [gx, gy])
		_pump_next_action()
		return
	# path 是 Vector2i 数组, 转像素路径
	_current_path = []
	for t in path:
		_current_path.append(Vector2(int(t.x) * TILE_SIZE + TILE_SIZE * 0.5, int(t.y) * TILE_SIZE + TILE_SIZE * 0.5))
	_path_idx = 0
	_state = State.WALKING
	_log_action(_clock.current_tick() if _clock else -1, "move", "→ (%d, %d)  path_len=%d" % [gx, gy, path.size()])

func _advance_along_path(delta: float) -> void:
	if _current_path.is_empty() or _path_idx >= _current_path.size():
		_state = State.IDLE
		_pump_next_action()
		return
	var target: Vector2 = _current_path[_path_idx]
	var dir: Vector2 = (target - global_position)
	var dist: float = dir.length()
	if dist < 1.0:
		_path_idx += 1
		return
	dir = dir / dist
	velocity = dir * move_speed_px
	move_and_slide()

# ------------------------------------------------------------------
# P1.5 — 视野感知 / 行动日志 / 观测接口
# ------------------------------------------------------------------
func _refresh_observation_if_needed() -> void:
	if _world == null or _clock == null:
		return
	var t: int = _clock.current_tick()
	if t - _last_observation_tick < observation_refresh_ticks:
		return
	_last_observation_tick = t
	var cx: int = int(floor(global_position.x / TILE_SIZE))
	var cy: int = int(floor(global_position.y / TILE_SIZE))
	var r: int = observation_radius_tiles
	var counts: Dictionary = {}
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy > r * r:
				continue
			var tx: int = cx + dx
			var ty: int = cy + dy
			var name: String = _tile_name(_world.tile_at(Vector2(tx * TILE_SIZE, ty * TILE_SIZE)))
			counts[name] = counts.get(name, 0) + 1
	var parts: PackedStringArray = []
	for k in counts.keys():
		parts.append("%s×%d" % [k, counts[k]])
	_observation_text = ", ".join(parts) if parts.size() > 0 else "(empty)"

func _tile_name(t: int) -> String:
	match t:
		0: return "grass"
		1: return "sand"
		2: return "water"
		3: return "tree"
		4: return "mountain"
		_: return "?"

func _maybe_log_position_change() -> void:
	if _world == null or _clock == null:
		return
	if global_position.distance_to(_last_position) < move_log_threshold_px:
		return
	var t: int = _clock.current_tick()
	var tile_x: int = int(floor(global_position.x / TILE_SIZE))
	var tile_y: int = int(floor(global_position.y / TILE_SIZE))
	# P2 状态机下, 行走由 A* 推动; move 日志由 _log_action 记录 (含 path_len)
	# 这里不再重复; 改为静默更新 _last_position
	_last_position = global_position

func _log_action(tick: int, kind: String, text: String) -> void:
	action_log.append({"tick": tick, "kind": kind, "text": text})
	if action_log.size() > action_log_max:
		action_log.pop_front()

# ------------------------------------------------------------------
# HUD 接口
# ------------------------------------------------------------------
func get_observation() -> String:
	return _observation_text

func get_action_log_lines(limit: int = 4) -> PackedStringArray:
	var n: int = mini(limit, action_log.size())
	var lines: PackedStringArray = []
	for i in range(action_log.size() - n, action_log.size()):
		var e: Dictionary = action_log[i]
		lines.append("  t%-4d  %-7s  %s" % [int(e.tick), str(e.kind), str(e.text)])
	return lines

func get_status_line() -> String:
	var tile_x: int = int(floor(global_position.x / TILE_SIZE))
	var tile_y: int = int(floor(global_position.y / TILE_SIZE))
	var t: int = _world.tile_at(global_position) if _world != null else -1
	var state_str: String = "WALKING" if _state == State.WALKING else "IDLE"
	var queue_n: int = _action_queue.size()
	return "agent=%s  state=%s  q=%d  pos=(%.1f, %.1f)  tile=(%d, %d)  terrain=%s" % [
		str(agent_id), state_str, queue_n,
		global_position.x, global_position.y, tile_x, tile_y, _tile_name(t)
	]

# ------------------------------------------------------------------
# P2 — 工具
# ------------------------------------------------------------------
func _find_nearest_walkable_tile(start: Vector2i) -> Vector2i:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = start + d
		if _world != null and _world.is_walkable_tile(n):
			return n
	return start
