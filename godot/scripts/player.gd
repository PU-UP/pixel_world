extends CharacterBody2D
class_name Player
##
## P1 玩家控制 + P1.5 可观测接口
##   - WASD/方向键 移动 (1 瓦片 = 16 px)
##   - 视野感知 (P1.5): 周围 6 瓦片内的 tile 类型 → observation 文本
##   - 行动日志 (P1.5): 最近 N 条 action 进栈
##   - P2 阶段会改为: 收到 MOVE_TO 原语后,A* 寻路并按路径点 walk
##

const GameWorldScript = preload("res://scripts/world/world.gd")
const GameClockScript = preload("res://scripts/world/clock.gd")
const TILE_SIZE: int = GameWorldScript.TILE_SIZE

@export var move_speed_px: float = 80.0   # 像素/秒,约 5 瓦片/秒
@export var body_color: Color = Color(0.78, 0.23, 0.23)  # 玩家红
@export var face_color: Color = Color(0.95, 0.78, 0.61)  # 肤色
@export var agent_id: StringName = &"player"
@export var display_name: String = "Player"
@export var observation_radius_tiles: int = 6
@export var observation_refresh_ticks: int = 2   # 观察刷新间隔(tick 数)
@export var action_log_max: int = 8
@export var move_log_threshold_px: float = 1.0  # 位移大于此值才记日志

# ---- 可观测状态(P1.5) ----
var _world: GameWorldScript = null
var _clock: GameClockScript = null
var _last_dir: Vector2 = Vector2.DOWN
var _last_position: Vector2 = Vector2.ZERO
var _last_observation_tick: int = -1
var _observation_text: String = "(no observation yet)"
var action_log: Array = []   # [{tick:int, kind:String, text:String}]

func _ready() -> void:
	# 程序生成 16x16 红色 sprite
	var img := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(body_color)
	# 头顶肤色"脸"
	for px in 4:
		for py in 3:
			img.set_pixel(6 + px, 2 + py, face_color)
	# 黑色描边
	img.set_pixel(0, 0, Color.BLACK); img.set_pixel(TILE_SIZE - 1, 0, Color.BLACK)
	img.set_pixel(0, TILE_SIZE - 1, Color.BLACK); img.set_pixel(TILE_SIZE - 1, TILE_SIZE - 1, Color.BLACK)
	for i in range(1, TILE_SIZE - 1):
		img.set_pixel(i, 0, Color.BLACK)
		img.set_pixel(i, TILE_SIZE - 1, Color.BLACK)
		img.set_pixel(0, i, Color.BLACK)
		img.set_pixel(TILE_SIZE - 1, i, Color.BLACK)
	var tex := ImageTexture.create_from_image(img)
	$Sprite2D.texture = tex
	_last_position = global_position

func bind_world(world: GameWorldScript) -> void:
	_world = world

func bind_clock(clock: GameClockScript) -> void:
	_clock = clock

func _physics_process(delta: float) -> void:
	var input := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_down")  - Input.get_action_strength("move_up")
	)
	if input.length() > 0.0:
		input = input.normalized()
		_last_dir = input

	velocity = input * move_speed_px
	move_and_slide()
	# 阻挡: 不能走到水/山/树
	if _world != null:
		# 用一个 4-向滑动的容错:检查中心点
		var center := global_position
		if not _world.is_walkable(center):
			# 弹回上一帧位置
			global_position -= input * move_speed_px * delta

	# 限制在世界范围内
	var half := TILE_SIZE * 0.5
	var size: Vector2 = _world.world_size() if _world else Vector2(1024, 1024)
	global_position.x = clamp(global_position.x, half, size.x - half)
	global_position.y = clamp(global_position.y, half, size.y - half)

	# ---- P1.5: 可观测性 hook ----
	_refresh_observation_if_needed()
	_maybe_log_position_change()

# ------------------------------------------------------------------
# P1.5 — 视野感知 / 行动日志
# ------------------------------------------------------------------
func _refresh_observation_if_needed() -> void:
	if _world == null or _clock == null:
		return
	var t := _clock.current_tick()
	if t - _last_observation_tick < observation_refresh_ticks:
		return
	_last_observation_tick = t

	var cx := int(floor(global_position.x / TILE_SIZE))
	var cy := int(floor(global_position.y / TILE_SIZE))
	var r := observation_radius_tiles
	var counts: Dictionary = {}   # tile_name -> count
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy > r * r:
				continue
			var tx := cx + dx
			var ty := cy + dy
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
	var t := _clock.current_tick()
	var tile_x := int(floor(global_position.x / TILE_SIZE))
	var tile_y := int(floor(global_position.y / TILE_SIZE))
	_log_action(t, "move", "→ tile (%d, %d)" % [tile_x, tile_y])
	_last_position = global_position

func _log_action(tick: int, kind: String, text: String) -> void:
	action_log.append({"tick": tick, "kind": kind, "text": text})
	if action_log.size() > action_log_max:
		action_log.pop_front()

# ------------------------------------------------------------------
# P1.5 — 给 HUD / 上层调用的查询接口
# ------------------------------------------------------------------
func get_observation() -> String:
	return _observation_text

func get_action_log_lines(limit: int = 4) -> PackedStringArray:
	var n := mini(limit, action_log.size())
	var lines: PackedStringArray = []
	for i in range(action_log.size() - n, action_log.size()):
		var e: Dictionary = action_log[i]
		lines.append("  t%-4d  %-4s  %s" % [int(e.tick), str(e.kind), str(e.text)])
	return lines

func get_status_line() -> String:
	var tile_x := int(floor(global_position.x / TILE_SIZE))
	var tile_y := int(floor(global_position.y / TILE_SIZE))
	var t: int = _world.tile_at(global_position) if _world != null else -1
	return "agent=%s  pos=(%.1f, %.1f)  tile=(%d, %d)  terrain=%s" % [
		str(agent_id), global_position.x, global_position.y, tile_x, tile_y, _tile_name(t)
	]
