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
const ExplorationMap = preload("res://scripts/world/exploration_map.gd")

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
var _comm = null        # CommRouter
var _obs_logger = null  # ObservabilityLogger
var _last_dir: Vector2 = Vector2.DOWN
var _last_position: Vector2 = Vector2.ZERO
var _last_observation_tick: int = -1
var _observation_text: String = "（尚无观察）"
var _heard_messages: Array = []
var _seen_emotes: Array = []
var _emote_text: String = ""
var _emote_left: float = 0.0
var _pending_reply_from: String = ""
var _pending_reply_text: String = ""
var _pending_reply_tick: int = -1
var _last_say_text: String = ""
var _last_say_tick: int = -1
var inventory: Array = []
var exploration: ExplorationMap = ExplorationMap.new()
var action_log: Array = []

const _ACTION_KIND_ZH: Dictionary = {
	"move": "移动",
	"say": "说话",
	"pickup": "拾取",
	"drop": "丢弃",
	"observe": "观察",
	"use": "使用",
	"give": "给予",
	"share_map": "共享地图",
	"wait": "等待",
	"sleep": "睡觉",
	"emote": "表情",
	"received": "收到",
	"heard": "听到",
}
var _selected: bool = false

# ---- P2 状态机 ----
enum State { IDLE, WALKING, WAITING, SLEEPING }
var _state: int = State.IDLE
var _action_queue: Array = []           # 待执行的 actions
var _current_action: Dictionary = {}    # 正在执行的
var _current_path: Array = []           # 像素路径 (Vector2)
var _path_idx: int = 0                  # 下一个要走的路径点索引
var _wait_remaining: int = 0
var _sleep_until_tick: int = 0
var _last_phase: String = ""
var _walk_anchor: Vector2 = Vector2.ZERO
var _walk_stuck_time: float = 0.0

# ---- Debug draw ----
var _debug_path: PackedVector2Array = PackedVector2Array()
var _pending_spawn: Variant = null

# ------------------------------------------------------------------
# 生命周期
# ------------------------------------------------------------------
func is_busy() -> bool:
	return _state == State.WALKING or _state == State.WAITING or _state == State.SLEEPING


func is_walking() -> bool:
	return _state == State.WALKING


func is_waiting() -> bool:
	return _state == State.WAITING


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
	collision_layer = 1
	collision_mask = 0
	_rebuild_sprite()
	_last_position = global_position


func set_body_color(c: Color) -> void:
	body_color = c
	if is_inside_tree():
		_rebuild_sprite()


func set_selected(on: bool) -> void:
	_selected = on
	queue_redraw()


func _rebuild_sprite() -> void:
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
	if has_node("Sprite2D"):
		$Sprite2D.texture = tex

func capture_save() -> Dictionary:
	var tile: Vector2i = get_tile_position()
	var data := {
		"id": str(agent_id),
		"tile": [tile.x, tile.y],
		"inventory": inventory.duplicate(),
		"exploration": exploration.to_dict(),
	}
	if _state == State.SLEEPING and _sleep_until_tick > 0:
		data["sleep_until_tick"] = _sleep_until_tick
	return data


func apply_save(row: Dictionary, restore_exploration: bool = true) -> void:
	clear_action_queue()
	var tile_arr: Array = row.get("tile", [])
	var tile := get_tile_position()
	if tile_arr.size() >= 2:
		tile = Vector2i(int(tile_arr[0]), int(tile_arr[1]))
	if _world != null and not _world.is_walkable_tile(tile):
		tile = _find_nearest_walkable_tile(tile)
	global_position = Vector2(tile.x * TILE_SIZE + TILE_SIZE * 0.5, tile.y * TILE_SIZE + TILE_SIZE * 0.5)
	_last_position = global_position
	inventory.clear()
	for it in row.get("inventory", []):
		var item_id: String = str(it).strip_edges()
		if not item_id.is_empty():
			inventory.append(item_id)
	if restore_exploration:
		var expl: Variant = row.get("exploration", {})
		if typeof(expl) == TYPE_DICTIONARY:
			exploration.from_dict(expl)
	_last_observation_tick = -1
	if _world != null:
		var now: int = _clock.current_tick() if _clock != null else 0
		exploration.update_observer(get_tile_position(), perception_radius(), _world, now)
	_restore_sleep(int(row.get("sleep_until_tick", 0)))


func bind_world(world) -> void:
	_world = world
	if _world != null:
		exploration.reset(_world.MAP_WIDTH, _world.MAP_HEIGHT)
	if is_inside_tree():
		_relocate_spawn()


func game_world() -> GameWorld:
	return _world


func current_tick() -> int:
	return _clock.current_tick() if _clock != null else 0

func bind_clock(clock) -> void:
	if _clock != null and _clock.tick.is_connected(_on_clock_tick):
		_clock.tick.disconnect(_on_clock_tick)
	_clock = clock
	if _clock != null and not _clock.tick.is_connected(_on_clock_tick):
		_clock.tick.connect(_on_clock_tick)


func bind_comm(comm) -> void:
	_comm = comm


func bind_observability(logger) -> void:
	_obs_logger = logger


func _interrupt_walk() -> void:
	_current_path.clear()
	_path_idx = 0
	_walk_stuck_time = 0.0
	_current_action = {}
	_state = State.IDLE
	modulate = Color.WHITE
	_pump_next_action()


func queued_action_count() -> int:
	return _action_queue.size()


func is_sleeping() -> bool:
	return _state == State.SLEEPING


func busy_state() -> String:
	if _state == State.SLEEPING:
		var left: int = maxi(0, _sleep_until_tick - current_tick())
		return "sleeping余%d" % left
	if _state == State.WAITING:
		return "waiting"
	if _state == State.WALKING:
		return "walking"
	return "idle"


func perception_radius() -> int:
	var base: int = observation_radius_tiles
	if _clock == null or not _clock.time_enabled() or not _clock.is_night():
		return base
	return maxi(2, int(round(float(base) * Config.time_night_perception_scale())))

# ------------------------------------------------------------------
# 公开接口 — 外部(LLM / 鼠标 / 键盘)灌入 action
# ------------------------------------------------------------------
func enqueue_action(action: Dictionary) -> void:
	var v: Dictionary = AgentActions.validate(action)
	if not v["ok"]:
		_log_action(_clock.current_tick() if _clock else -1, "reject", "invalid: %s" % v["error"])
		_log_obs_action(str(action.get("kind", "?")), action.get("params", {}), false, v["error"], v["error"])
		printerr("[Player] reject action: ", v["error"], " action=", action)
		return
	# 已实现校验
	if action["kind"] not in AgentActions.IMPLEMENTED_KINDS:
		_log_action(_clock.current_tick() if _clock else -1, "reject", "unimplemented: %s" % action["kind"])
		_log_obs_action(action["kind"], action.get("params", {}), false, "unimplemented", action["kind"])
		printerr("[Player] kind not implemented in P2: ", action["kind"])
		return
	_action_queue.append(action)
	_log_action(_clock.current_tick() if _clock else -1, "enqueue", AgentActions.format_action(action))
	if _state == State.IDLE:
		_pump_next_action()
	elif _state == State.WALKING:
		_interrupt_walk()

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
	_wait_remaining = 0
	_sleep_until_tick = 0
	_walk_stuck_time = 0.0
	_state = State.IDLE
	modulate = Color.WHITE
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

	if _emote_left > 0.0:
		_emote_left -= delta
		if _emote_left <= 0.0:
			_emote_text = ""
			_emote_left = 0.0
		queue_redraw()

	# ---- P1.5 观测/日志 hook ----
	_refresh_observation_if_needed()
	_maybe_log_position_change()
	if _selected or _state == State.SLEEPING or _emote_left > 0.0 or (debug_show_path and not _current_path.is_empty()):
		queue_redraw()

func _draw() -> void:
	if _selected:
		draw_arc(Vector2.ZERO, TILE_SIZE * 0.55, 0.0, TAU, 24, Color(1.0, 0.95, 0.3, 0.85), 2.0)
	if _state == State.SLEEPING:
		draw_circle(Vector2(5, -9), 2.0, Color(0.85, 0.9, 1.0, 0.95))
		draw_circle(Vector2(9, -13), 2.4, Color(0.85, 0.9, 1.0, 0.95))
		draw_circle(Vector2(13, -17), 2.8, Color(0.85, 0.9, 1.0, 0.95))
	if not _emote_text.is_empty():
		_draw_emote_bubble()
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
		AgentActions.KIND_SAY:
			_execute_say(_current_action)
		AgentActions.KIND_EMOTE:
			_execute_emote(_current_action)
		AgentActions.KIND_PICK_UP:
			_execute_pick_up(_current_action)
		AgentActions.KIND_DROP:
			_execute_drop(_current_action)
		AgentActions.KIND_OBSERVE:
			_execute_observe(_current_action)
		AgentActions.KIND_USE:
			_execute_use(_current_action)
		AgentActions.KIND_GIVE:
			_execute_give(_current_action)
		AgentActions.KIND_SHARE_MAP:
			_execute_share_map(_current_action)
		AgentActions.KIND_WAIT:
			_execute_wait(_current_action)
		AgentActions.KIND_SLEEP:
			_execute_sleep(_current_action)
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
		_log_obs_action(AgentActions.KIND_MOVE_TO, {"x": gx, "y": gy}, true, "already at target")
		_pump_next_action()
		return
	var path: Array = AStarPathfinder.find_path(_world, start_tile, goal_tile)
	if path.is_empty():
		_log_action(_clock.current_tick() if _clock else -1, "move", "UNREACHABLE (%d, %d)" % [gx, gy])
		_log_obs_action(AgentActions.KIND_MOVE_TO, {"x": gx, "y": gy}, false, "unreachable", "path empty")
		_pump_next_action()
		return
	# path 是 Vector2i 数组, 转像素路径
	_current_path = []
	for t in path:
		_current_path.append(Vector2(int(t.x) * TILE_SIZE + TILE_SIZE * 0.5, int(t.y) * TILE_SIZE + TILE_SIZE * 0.5))
	_path_idx = 0
	_walk_anchor = global_position
	_walk_stuck_time = 0.0
	_state = State.WALKING
	_log_action(_clock.current_tick() if _clock else -1, "move", "→ (%d, %d)  path_len=%d" % [gx, gy, path.size()])
	_log_obs_action(AgentActions.KIND_MOVE_TO, {"x": gx, "y": gy}, true, "path_len=%d" % path.size())

func _execute_say(action: Dictionary) -> void:
	var p: Dictionary = action["params"]
	var tick: int = _clock.current_tick() if _clock else -1
	var to_s: String = str(p.get("to", ""))
	var text_s: String = str(p.get("text", ""))
	var tone_s: String = str(p.get("tone", "neutral"))
	if _comm == null:
		_log_action(tick, "say", "FAILED no comm router")
		_log_obs_action(AgentActions.KIND_SAY, p, false, "no comm router")
	else:
		var res: Dictionary = _comm.deliver_say(self, to_s, text_s, tone_s, tick)
		if res.get("ok", false):
			_log_action(tick, "say", "→ %s: %s" % [to_s, text_s])
			record_successful_say(to_s, text_s, tick)
			_log_obs_say(to_s, text_s, tone_s, tick, res.get("recipient_ids", []), true)
			_log_obs_action(AgentActions.KIND_SAY, p, true, "→ %s: %s" % [to_s, text_s])
		else:
			var err: String = str(res.get("error", "?"))
			_log_action(tick, "say", "FAILED %s" % err)
			_log_obs_say(to_s, text_s, tone_s, tick, [], false, err)
			_log_obs_action(AgentActions.KIND_SAY, p, false, err, err)
	_pump_next_action()


func _execute_emote(action: Dictionary) -> void:
	var p: Dictionary = action["params"]
	var emoji: String = str(p.get("emoji", "")).strip_edges()
	var tick: int = _clock.current_tick() if _clock else -1
	if emoji.is_empty():
		_log_action(tick, "emote", "FAILED empty emoji")
		_log_obs_action(AgentActions.KIND_EMOTE, p, false, "empty emoji")
		_pump_next_action()
		return
	_emote_text = emoji
	_emote_left = Config.emote_display_seconds()
	queue_redraw()
	var seen: Array = []
	if _comm != null:
		var res: Dictionary = _comm.deliver_emote(self, emoji, tick)
		if res.get("ok", false):
			seen = res.get("recipient_ids", [])
		else:
			var err: String = str(res.get("error", "?"))
			_log_action(tick, "emote", "FAILED %s" % err)
			_log_obs_action(AgentActions.KIND_EMOTE, p, false, err, err)
			_pump_next_action()
			return
	_log_action(tick, "emote", emoji)
	_log_obs_action(AgentActions.KIND_EMOTE, p, true, emoji if seen.is_empty() else "%s → %s" % [emoji, ",".join(PackedStringArray(seen))])
	_pump_next_action()


func _draw_emote_bubble() -> void:
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return
	var font_size: int = 10
	var sz: Vector2 = font.get_string_size(_emote_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var origin := Vector2(-sz.x * 0.5, -16.0)
	var pad := Vector2(3.0, 2.0)
	var rect := Rect2(origin + Vector2(-pad.x, -sz.y - 1.0), sz + pad * 2.0)
	draw_rect(rect, Color(0.08, 0.08, 0.12, 0.86), true)
	draw_rect(rect, Color(1.0, 0.95, 0.7, 0.55), false, 1.0)
	draw_string(font, origin, _emote_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1.0, 0.96, 0.78))


func _execute_pick_up(action: Dictionary) -> void:
	var p: Dictionary = action["params"]
	var item_id: String = str(p.get("item", ""))
	var tick: int = _clock.current_tick() if _clock else -1
	if _world == null or _world.state == null:
		_log_action(tick, "pickup", "FAILED no world state")
		_log_obs_action(AgentActions.KIND_PICK_UP, p, false, "no world state")
	else:
		var res: Dictionary = _world.state.try_pick_up(get_tile_position(), item_id)
		if res.get("ok", false):
			inventory.append(str(res.get("item_id", item_id)))
			_log_action(tick, "pickup", "got %s" % res.get("item_id", item_id))
			_log_obs_action(AgentActions.KIND_PICK_UP, p, true, "got %s" % res.get("item_id", item_id))
		else:
			var err: String = str(res.get("error", "?"))
			_log_action(tick, "pickup", "FAILED %s" % err)
			_log_obs_action(AgentActions.KIND_PICK_UP, p, false, err, err)
	_pump_next_action()


func _execute_drop(action: Dictionary) -> void:
	var p: Dictionary = action["params"]
	var item_id: String = str(p.get("item", ""))
	var tick: int = _clock.current_tick() if _clock else -1
	if not inventory.has(item_id):
		_log_action(tick, "drop", "FAILED not carrying %s" % item_id)
		_log_obs_action(AgentActions.KIND_DROP, p, false, "not carrying", item_id)
	elif _world == null or _world.state == null:
		_log_action(tick, "drop", "FAILED no world state")
		_log_obs_action(AgentActions.KIND_DROP, p, false, "no world state")
	else:
		inventory.erase(item_id)
		var res: Dictionary = _world.state.try_drop(get_tile_position(), item_id)
		if res.get("ok", false):
			_log_action(tick, "drop", "dropped %s" % item_id)
			_log_obs_action(AgentActions.KIND_DROP, p, true, "dropped %s" % item_id)
		else:
			inventory.append(item_id)
			var err: String = str(res.get("error", "?"))
			_log_action(tick, "drop", "FAILED %s" % err)
			_log_obs_action(AgentActions.KIND_DROP, p, false, err, err)
	_pump_next_action()


func _execute_observe(action: Dictionary) -> void:
	var p: Dictionary = action["params"]
	var target: String = str(p.get("target", "")).strip_edges()
	var tick: int = _clock.current_tick() if _clock else -1
	var detail: String = ""
	if _comm != null:
		for other in _comm.players_in_perception(self):
			if str(other.agent_id) == target:
				var ot: Vector2i = other.get_tile_position()
				detail = "agent %s at (%d,%d) inv=%s" % [
					target, ot.x, ot.y, other._inventory_summary(),
				]
				break
	if detail.is_empty() and _world != null and _world.state != null:
		var found: Dictionary = _world.state.find_ground_item_near(
			get_tile_position(), target, perception_radius()
		)
		if not found.is_empty():
			var it: Vector2i = found.get("tile", Vector2i.ZERO)
			detail = "%s at (%d,%d): %s" % [
				target, it.x, it.y, _world.state.describe_item(target),
			]
	if detail.is_empty():
		_log_action(tick, "observe", "FAILED unknown/range %s" % target)
		_log_obs_action(AgentActions.KIND_OBSERVE, p, false, "unknown/range", target)
	else:
		_log_action(tick, "observe", detail.substr(0, 72))
		_log_obs_action(AgentActions.KIND_OBSERVE, p, true, detail.substr(0, 120))
	_pump_next_action()


func _execute_use(action: Dictionary) -> void:
	var p: Dictionary = action["params"]
	var item_id: String = str(p.get("item", "")).strip_edges()
	var on_target: String = str(p.get("on", "")).strip_edges()
	var tick: int = _clock.current_tick() if _clock else -1
	if item_id.is_empty():
		_log_action(tick, "use", "FAILED empty item")
		_log_obs_action(AgentActions.KIND_USE, p, false, "empty item")
	elif not inventory.has(item_id):
		_log_action(tick, "use", "FAILED not carrying %s" % item_id)
		_log_obs_action(AgentActions.KIND_USE, p, false, "not carrying", item_id)
	elif not _use_target_valid(on_target):
		_log_action(tick, "use", "FAILED target out of range: %s" % on_target)
		_log_obs_action(AgentActions.KIND_USE, p, false, "target out of range", on_target)
	else:
		var defs: Dictionary = Config.world_item_defs()
		var def: Dictionary = defs.get(item_id, {})
		var text: String = str(def.get("use_text", "used %s" % item_id))
		if on_target not in ["self", str(agent_id)]:
			text = "%s (on %s)" % [text, on_target]
		if bool(def.get("consumable", false)):
			inventory.erase(item_id)
		_log_action(tick, "use", text)
		_log_obs_action(AgentActions.KIND_USE, p, true, text)
	_pump_next_action()


func _execute_give(action: Dictionary) -> void:
	var p: Dictionary = action["params"]
	var item_id: String = str(p.get("item", "")).strip_edges()
	var to_id: String = str(p.get("to", "")).strip_edges()
	var tick: int = _clock.current_tick() if _clock else -1
	if _comm == null:
		_log_action(tick, "give", "FAILED no comm router")
		_log_obs_action(AgentActions.KIND_GIVE, p, false, "no comm router")
	elif item_id.is_empty() or to_id.is_empty():
		_log_action(tick, "give", "FAILED empty item or target")
		_log_obs_action(AgentActions.KIND_GIVE, p, false, "empty item or target")
	else:
		var res: Dictionary = _comm.deliver_give(self, to_id, item_id, tick)
		if res.get("ok", false):
			_log_action(tick, "give", "→ %s: %s" % [to_id, item_id])
			_log_obs_action(AgentActions.KIND_GIVE, p, true, "→ %s: %s" % [to_id, item_id])
		else:
			var err: String = str(res.get("error", "?"))
			_log_action(tick, "give", "FAILED %s" % err)
			_log_obs_action(AgentActions.KIND_GIVE, p, false, err, err)
	_pump_next_action()


func _execute_share_map(action: Dictionary) -> void:
	var p: Dictionary = action["params"]
	var to_id: String = str(p.get("to", "")).strip_edges()
	var tick: int = _clock.current_tick() if _clock else -1
	if _comm == null:
		_log_action(tick, "share_map", "FAILED no comm router")
		_log_obs_action(AgentActions.KIND_SHARE_MAP, p, false, "no comm router")
	elif to_id.is_empty():
		_log_action(tick, "share_map", "FAILED empty target")
		_log_obs_action(AgentActions.KIND_SHARE_MAP, p, false, "empty target")
	else:
		var res: Dictionary = _comm.deliver_share_map(self, to_id, tick)
		if res.get("ok", false):
			var detail: String = "→ %s" % to_id
			if res.get("mutual", false):
				detail += " (merged %d tiles)" % int(res.get("merged", 0))
			else:
				detail += " (pending consensus)"
			_log_action(tick, "share_map", detail)
			_log_obs_action(AgentActions.KIND_SHARE_MAP, p, true, detail)
		else:
			var err: String = str(res.get("error", "?"))
			_log_action(tick, "share_map", "FAILED %s" % err)
			_log_obs_action(AgentActions.KIND_SHARE_MAP, p, false, err, err)
	_pump_next_action()


func _execute_wait(action: Dictionary) -> void:
	var ticks: int = int(action.get("params", {}).get("ticks", 1))
	var max_wait: int = Config.decision_wait_max_ticks()
	ticks = clampi(ticks, 1, max_wait)
	var tick: int = _clock.current_tick() if _clock else -1
	_wait_remaining = ticks
	_state = State.WAITING
	modulate = Color.WHITE
	_log_action(tick, "wait", "%d ticks" % ticks)
	_log_obs_action(AgentActions.KIND_WAIT, action.get("params", {}), true, "wait %d" % ticks)


func _execute_sleep(action: Dictionary) -> void:
	var until_tick: int = int(action.get("params", {}).get("until_tick", 0))
	var now: int = _clock.current_tick() if _clock else 0
	var max_sleep: int = Config.time_sleep_max_ticks()
	until_tick = clampi(until_tick, now + 1, now + max_sleep)
	_enter_sleep(until_tick)
	_log_action(now, "sleep", "until t%d" % until_tick)
	_log_obs_action(AgentActions.KIND_SLEEP, action.get("params", {}), true, "until t%d" % until_tick)


func _enter_sleep(until_tick: int) -> void:
	_sleep_until_tick = until_tick
	_state = State.SLEEPING
	modulate = Color(0.62, 0.64, 0.82)
	queue_redraw()


func _restore_sleep(until_tick: int) -> void:
	if until_tick <= current_tick():
		return
	_enter_sleep(until_tick)


func _on_clock_tick(_tick_index: int) -> void:
	if _clock != null:
		var p: String = _clock.phase()
		if p != _last_phase:
			_last_phase = p
			_last_observation_tick = -1
	if _state == State.WAITING:
		_wait_remaining -= 1
		if _wait_remaining > 0:
			return
		_wait_remaining = 0
		_finish_idle()
		return
	if _state != State.SLEEPING:
		return
	if _clock != null and _clock.current_tick() < _sleep_until_tick:
		return
	_sleep_until_tick = 0
	_finish_idle()


func _finish_idle() -> void:
	_state = State.IDLE
	modulate = Color.WHITE
	_current_action = {}
	_pump_next_action()


func _use_target_valid(on_target: String) -> bool:
	if on_target.is_empty() or on_target in ["self", str(agent_id)]:
		return true
	if _comm != null:
		for other in _comm.players_in_perception(self):
			if str(other.agent_id) == on_target:
				return true
	if _world != null and _world.state != null:
		var found: Dictionary = _world.state.find_ground_item_near(
			get_tile_position(), on_target, perception_radius()
		)
		if not found.is_empty():
			var item_tile: Vector2i = found.get("tile", Vector2i.ZERO)
			if _world.has_line_of_sight(get_tile_position(), item_tile):
				return true
	return false


func receive_say(from_id: String, text: String, _tone: String, tick: int) -> void:
	_heard_messages.append({"from": from_id, "text": text, "tick": tick})
	if _heard_messages.size() > 6:
		_heard_messages.pop_front()
	_pending_reply_from = from_id
	_pending_reply_text = text
	_pending_reply_tick = tick
	_log_action(tick, "heard", "%s: %s" % [from_id, text])


func receive_emote(from_id: String, emoji: String, tick: int) -> void:
	_seen_emotes.append({"from": from_id, "emoji": emoji, "tick": tick})
	if _seen_emotes.size() > 6:
		_seen_emotes.pop_front()
	_log_action(tick, "emote", "看见 %s %s" % [from_id, emoji])


func current_emote() -> String:
	if _emote_left <= 0.0:
		return ""
	return _emote_text


func receive_item(from_id: String, item_id: String, tick: int) -> void:
	inventory.append(item_id)
	_log_action(tick, "received", "%s gave %s" % [from_id, item_id])


func receive_share_offer(from_id: String, tick: int) -> void:
	_log_action(tick, "heard", "%s 提议共享已探索地图（需双方 SHARE_MAP 达成一致）" % from_id)


func get_recent_heard_lines(limit: int = 4) -> PackedStringArray:
	var lines: PackedStringArray = []
	var n: int = mini(limit, _heard_messages.size())
	for i in range(_heard_messages.size() - n, _heard_messages.size()):
		var m: Dictionary = _heard_messages[i]
		lines.append("t%d %s说: %s" % [int(m.get("tick", -1)), str(m.get("from", "?")), str(m.get("text", ""))])
	return lines


func get_recent_emote_lines(limit: int = 4) -> PackedStringArray:
	var lines: PackedStringArray = []
	var n: int = mini(limit, _seen_emotes.size())
	for i in range(_seen_emotes.size() - n, _seen_emotes.size()):
		var m: Dictionary = _seen_emotes[i]
		lines.append("t%d %s: %s" % [int(m.get("tick", -1)), str(m.get("from", "?")), str(m.get("emoji", ""))])
	return lines


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
	var cfg: Dictionary = Config.movement_cfg()
	var abort_s: float = float(cfg.get("stuck_abort_s", 1.5))
	var min_disp: float = float(cfg.get("stuck_min_displacement_px", 2.0))
	if global_position.distance_to(_walk_anchor) >= min_disp:
		_walk_anchor = global_position
		_walk_stuck_time = 0.0
	else:
		_walk_stuck_time += delta
		if abort_s > 0.0 and _walk_stuck_time >= abort_s:
			_abort_stuck_move()


func _abort_stuck_move() -> void:
	var tick: int = _clock.current_tick() if _clock else -1
	var tile: Vector2i = get_tile_position()
	_current_path = []
	_path_idx = 0
	_walk_stuck_time = 0.0
	_state = State.IDLE
	_current_action = {}
	_log_action(tick, "move", "stuck abort at (%d, %d)" % [tile.x, tile.y])
	_log_obs_action(AgentActions.KIND_MOVE_TO, {"x": tile.x, "y": tile.y}, true, "movement_stuck")
	if _obs_logger != null:
		_obs_logger.log_movement_stuck(str(agent_id), tick, tile)
	_pump_next_action()

# ------------------------------------------------------------------
# P1.5 — 视野感知 / 行动日志 / 观测接口
# ------------------------------------------------------------------
func _refresh_observation_if_needed() -> void:
	if _world == null or _clock == null:
		return
	var t: int = _clock.current_tick()
	if _last_observation_tick >= 0 and t - _last_observation_tick < observation_refresh_ticks:
		return
	_last_observation_tick = t
	var cx: int = int(floor(global_position.x / TILE_SIZE))
	var cy: int = int(floor(global_position.y / TILE_SIZE))
	var region_name: String = "wilderness"
	if _world != null and _world.state != null:
		region_name = _world.state.region_name_at(Vector2i(cx, cy))
	var r: int = perception_radius()
	var counts: Dictionary = {}
	var origin := Vector2i(cx, cy)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy > r * r:
				continue
			var tx: int = cx + dx
			var ty: int = cy + dy
			if not _world.has_line_of_sight(origin, Vector2i(tx, ty)):
				continue
			var name: String = _tile_name(_world.tile_at(Vector2(tx * TILE_SIZE, ty * TILE_SIZE)))
			counts[name] = counts.get(name, 0) + 1
	var parts: PackedStringArray = []
	for k in counts.keys():
		parts.append("%s×%d" % [k, counts[k]])
	var terrain_text := ", ".join(parts) if parts.size() > 0 else "（空）"
	var agent_parts: PackedStringArray = []
	if _comm != null:
		for p in _comm.players_in_perception(self):
			var pt: Vector2i = p.get_tile_position()
			var extra := ""
			if p.is_sleeping():
				extra = " 入睡"
			var face: String = p.current_emote()
			if not face.is_empty():
				extra += " %s" % face
			agent_parts.append("%s@(%d,%d)%s" % [str(p.agent_id), pt.x, pt.y, extra])
	if agent_parts.size() > 0:
		_observation_text = "区域=%s | %s | 附近角色: %s" % [region_name, terrain_text, ", ".join(agent_parts)]
	else:
		_observation_text = "区域=%s | %s" % [region_name, terrain_text]
	var item_parts: PackedStringArray = []
	if _world != null and _world.state != null:
		for item in _world.state.items_near(Vector2i(cx, cy), r):
			var item_tile: Vector2i = item.get("tile", Vector2i.ZERO)
			if not _world.has_line_of_sight(Vector2i(cx, cy), item_tile):
				continue
			item_parts.append("%s@(%d,%d)" % [str(item.get("item_id", "?")), item_tile.x, item_tile.y])
	if item_parts.size() > 0:
		_observation_text += " | 物品: " + ", ".join(item_parts)
	if _world.events != null:
		var event_lines: PackedStringArray = _world.events.lines_for_tile(Vector2i(cx, cy))
		if event_lines.size() > 0:
			_observation_text += " | 事件: " + event_lines[0]
	var heard := get_recent_heard_lines(2)
	if heard.size() > 0:
		_observation_text += " | 听到: " + "; ".join(heard)
	var emotes := get_recent_emote_lines(2)
	if emotes.size() > 0:
		_observation_text += " | 表情: " + "; ".join(emotes)
	if _clock != null and _clock.time_enabled():
		_observation_text = "%s 下次黎明t%d | %s" % [
			_clock.format_phase_clock(),
			_clock.next_dawn_tick(),
			_observation_text,
		]
	exploration.update_observer(Vector2i(cx, cy), r, _world, t)

func _tile_name(t: int) -> String:
	match t:
		0: return "草地"
		1: return "沙滩"
		2: return "水域"
		3: return "树林"
		4: return "山地"
		_: return "未知"

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


func _log_obs_action(
	kind: String,
	params: Dictionary,
	ok: bool,
	detail: String,
	error: String = "",
) -> void:
	if _obs_logger == null:
		return
	var tick: int = _clock.current_tick() if _clock else -1
	_obs_logger.log_action_result(str(agent_id), tick, kind, params, ok, detail, error)


func _log_obs_say(
	target_id: String,
	text: String,
	tone: String,
	tick: int,
	recipient_ids: Array,
	ok: bool,
	error: String = "",
) -> void:
	if _obs_logger == null:
		return
	_obs_logger.log_say(str(agent_id), target_id, text, tick, recipient_ids, ok, error, tone)

# ------------------------------------------------------------------
# HUD 接口
# ------------------------------------------------------------------
func get_observation() -> String:
	_refresh_observation_if_needed()
	return _observation_text


func get_observation_for_llm() -> String:
	_refresh_observation_if_needed()
	var text := _observation_text
	var idx: int = text.find("| 听到:")
	if idx >= 0:
		return text.substr(0, idx).strip_edges()
	return text


func get_pending_reply_from() -> String:
	return _pending_reply_from


func get_pending_reply_line() -> String:
	if _pending_reply_from.is_empty():
		return ""
	return "t%d %s说: %s" % [_pending_reply_tick, _pending_reply_from, _pending_reply_text]


func get_last_say_text() -> String:
	return _last_say_text


func would_repeat_say(text: String) -> bool:
	var normalized := text.strip_edges()
	if normalized.is_empty() or normalized != _last_say_text:
		return false
	var window: int = Config.decision_repeat_say_block_ticks()
	if _clock == null or window <= 0:
		return true
	return _clock.current_tick() - _last_say_tick <= window


func record_successful_say(to: String, text: String, tick: int) -> void:
	_last_say_text = text.strip_edges()
	_last_say_tick = tick
	var target := to.strip_edges()
	if target != "broadcast" and target == _pending_reply_from:
		_clear_pending_reply()


func _clear_pending_reply() -> void:
	_pending_reply_from = ""
	_pending_reply_text = ""
	_pending_reply_tick = -1

func get_action_log_lines(limit: int = 4) -> PackedStringArray:
	var n: int = mini(limit, action_log.size())
	var lines: PackedStringArray = []
	for i in range(action_log.size() - n, action_log.size()):
		var e: Dictionary = action_log[i]
		var kind: String = str(e.kind)
		var kind_zh: String = str(_ACTION_KIND_ZH.get(kind, kind))
		lines.append("  t%-4d  %-4s  %s" % [int(e.tick), kind_zh, str(e.text)])
	return lines

func get_status_line() -> String:
	var tile_x: int = int(floor(global_position.x / TILE_SIZE))
	var tile_y: int = int(floor(global_position.y / TILE_SIZE))
	var t: int = _world.tile_at(global_position) if _world != null else -1
	var queue_n: int = _action_queue.size()
	var state_zh := "空闲"
	if _state == State.WALKING:
		state_zh = "行走"
	elif _state == State.WAITING:
		state_zh = "等待"
	elif _state == State.SLEEPING:
		state_zh = "睡觉余%d" % maxi(0, _sleep_until_tick - current_tick())
	var time_s := ""
	if _clock != null and _clock.time_enabled():
		time_s = "  %s" % _clock.format_phase_clock()
	return "角色=%s  状态=%s  队列=%d  背包=%s  坐标=(%d,%d)  地形=%s%s" % [
		str(agent_id),
		state_zh,
		queue_n,
		_inventory_summary(),
		tile_x,
		tile_y,
		_tile_name(t),
		time_s,
	]


func _inventory_summary() -> String:
	if inventory.is_empty():
		return "空"
	return ",".join(inventory)


func get_nearby_item_lines() -> PackedStringArray:
	var lines: PackedStringArray = []
	if _world == null or _world.state == null:
		return lines
	for item in _world.state.items_near(get_tile_position(), Config.world_item_pickup_radius() + 1):
		var t: Vector2i = item.get("tile", Vector2i.ZERO)
		lines.append("%s（%s）在 (%d,%d)" % [
			str(item.get("item_id", "")),
			str(item.get("display_name", "")),
			t.x, t.y,
		])
	return lines

# ------------------------------------------------------------------
# P2 — 工具
# ------------------------------------------------------------------
func _find_nearest_walkable_tile(start: Vector2i) -> Vector2i:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = start + d
		if _world != null and _world.is_walkable_tile(n):
			return n
	return start
