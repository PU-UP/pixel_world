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
const AgentVitals = preload("res://scripts/agent/vitals.gd")

signal died

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
var _dwell_anchor: Vector2i = Vector2i.ZERO
var _dwell_ticks: int = 0
var _frontier_cache_tick: int = -999
var _frontier_cache: Array = []
var _walk_sight_ids: Dictionary = {}
var _walk_vitals_nudge_done: bool = false
var _follow_id: String = ""
var _follow_until_tick: int = 0
var _follow_internal: bool = false
var _relationships = null
var inventory: Array = []
var vitals: AgentVitals = AgentVitals.new()
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
	"mark": "铭刻",
	"follow": "跟随",
	"meet": "约定",
	"received": "收到",
	"heard": "听到",
	"die": "死亡",
}
var _selected: bool = false

# ---- P2 状态机 ----
enum State { IDLE, WALKING, WAITING, SLEEPING, DEAD }
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
	return (
		_state == State.WALKING
		or _state == State.WAITING
		or _state == State.SLEEPING
		or _state == State.DEAD
	)


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
	var extra: Array = []
	if cfg.has("starting_items") and typeof(cfg["starting_items"]) == TYPE_ARRAY:
		extra = cfg["starting_items"]
	seed_starting_inventory(extra)


func seed_starting_inventory(extra: Array = []) -> void:
	if not inventory.is_empty():
		return
	for item_id in Config.vitals_starting_food():
		if Config.can_carry_item(inventory, item_id):
			inventory.append(item_id)
	for raw in extra:
		var item_id: String = str(raw).strip_edges()
		if item_id.is_empty():
			continue
		if Config.can_carry_item(inventory, item_id):
			inventory.append(item_id)


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
	vitals.reset()
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
		"vitals": vitals.capture_save(),
	}
	if _state == State.SLEEPING and _sleep_until_tick > 0:
		data["sleep_until_tick"] = _sleep_until_tick
	if is_dead():
		data["dead"] = true
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
	var vitals_raw: Variant = row.get("vitals", {})
	if typeof(vitals_raw) == TYPE_DICTIONARY:
		vitals.apply_save(vitals_raw)
	else:
		vitals.reset()
	_last_observation_tick = -1
	_dwell_ticks = 0
	_dwell_anchor = get_tile_position()
	_frontier_cache_tick = -999
	_frontier_cache = []
	if _world != null:
		var now: int = _clock.current_tick() if _clock != null else 0
		exploration.update_observer(get_tile_position(), perception_radius(), _world, now)
	if bool(row.get("dead", false)) or vitals.is_deceased():
		_become_corpse(false)
	else:
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


func bind_relationships(rel) -> void:
	_relationships = rel


func bind_observability(logger) -> void:
	_obs_logger = logger


func is_following() -> bool:
	return not _follow_id.strip_edges().is_empty()


func following_id() -> String:
	return _follow_id


func clear_follow() -> void:
	_follow_id = ""
	_follow_until_tick = 0
	_follow_internal = false


func near_campfire() -> bool:
	if _world == null or _world.state == null:
		return false
	return _world.state.is_near_campfire(get_tile_position())


func _storm_energy_scale() -> float:
	if _world == null or _world.events == null:
		return 1.0
	return _world.events.storm_energy_scale_at(get_tile_position())


func refuses_gift_from(giver_id: String) -> bool:
	if _relationships == null:
		return false
	var cfg: Dictionary = Config.relationships_cfg()
	var e: Dictionary = _relationships.get_edge(giver_id)
	var fam_min: float = float(cfg.get("give_refuse_familiarity", 0.35))
	var aff_max: float = float(cfg.get("give_refuse_affinity_below", 0.12))
	return float(e.get("familiarity", 0.0)) >= fam_min and float(e.get("affinity", 0.0)) < aff_max


func receive_meet(from_id: String, tile: Vector2i, until_tick: int, tick: int) -> void:
	if is_dead():
		return
	_log_action(tick, "meet", "%s 约在 (%d,%d) 至 t%d" % [from_id, tile.x, tile.y, until_tick])


func _retarget_follow() -> bool:
	if not is_following() or is_dead() or is_sleeping():
		return false
	var tick: int = current_tick()
	if _follow_until_tick > 0 and tick >= _follow_until_tick:
		clear_follow()
		return false
	if _comm == null:
		clear_follow()
		return false
	var other: Player = _comm.find_player(_follow_id)
	if other == null or other.is_dead():
		clear_follow()
		return false
	var in_sight := false
	for seen in _comm.players_in_sight(self):
		if seen == other:
			in_sight = true
			break
	if not in_sight:
		clear_follow()
		return false
	if is_walking() or is_waiting():
		return true
	var occupied: Array = []
	for p in _comm.all_players():
		if p == self:
			continue
		occupied.append("%d,%d" % [p.get_tile_position().x, p.get_tile_position().y])
	var meet: Dictionary = AgentActions.resolve_meeting_tile(
		_world, get_tile_position(), other.get_tile_position(), occupied
	)
	if not meet.get("ok", false):
		return false
	var dest: Vector2i = meet.get("tile", get_tile_position())
	if dest == get_tile_position():
		_snapshot_walk_sight()
		return false
	_follow_internal = true
	enqueue_action(AgentActions.make_move_to(dest.x, dest.y))
	_follow_internal = false
	return true


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


func is_dead() -> bool:
	return _state == State.DEAD


func busy_state() -> String:
	if _state == State.DEAD:
		return "dead"
	if _state == State.SLEEPING:
		var left: int = maxi(0, _sleep_until_tick - current_tick())
		return "sleeping余%d" % left
	if _state == State.WAITING:
		return "waiting"
	if _state == State.WALKING:
		if is_following():
			return "follow %s" % _follow_id
		return "walking"
	if is_following():
		return "follow %s" % _follow_id
	return "idle"


func perception_radius() -> int:
	var base: int = observation_radius_tiles
	var r: int = base
	if _clock != null and _clock.time_enabled() and _clock.is_night():
		r = maxi(2, int(round(float(base) * Config.time_night_perception_scale())))
		if near_campfire():
			r += Config.traces_campfire_vision_bonus()
	return r

# ------------------------------------------------------------------
# 公开接口 — 外部(LLM / 鼠标 / 键盘)灌入 action
# ------------------------------------------------------------------
func enqueue_action(action: Dictionary) -> void:
	if is_dead():
		_log_action(_clock.current_tick() if _clock else -1, "reject", "dead")
		_log_obs_action(str(action.get("kind", "?")), action.get("params", {}), false, "dead")
		return
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
	if is_following() and not _follow_internal:
		if str(action.get("kind", "")) != AgentActions.KIND_FOLLOW:
			clear_follow()
	_action_queue.append(action)
	_log_action(_clock.current_tick() if _clock else -1, "enqueue", AgentActions.format_action(action))
	if _state == State.WALKING and not AgentActions.interrupts_walk(str(action.get("kind", ""))):
		_dedupe_queued_moves()
		return
	if _state == State.WAITING:
		if not AgentActions.interrupts_walk(str(action.get("kind", ""))):
			_dedupe_queued_moves()
			return
		_wait_remaining = 0
		_state = State.IDLE
		modulate = Color.WHITE
		_current_action = {}
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
	clear_follow()

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
	_draw_vital_bars()
	if _state == State.DEAD:
		draw_line(Vector2(-5, -5), Vector2(5, 5), Color(0.62, 0.14, 0.14, 0.95), 1.6)
		draw_line(Vector2(-5, 5), Vector2(5, -5), Color(0.62, 0.14, 0.14, 0.95), 1.6)
	if _state == State.SLEEPING:
		draw_circle(Vector2(10, -8), 2.0, Color(0.85, 0.9, 1.0, 0.95))
		draw_circle(Vector2(13, -12), 2.4, Color(0.85, 0.9, 1.0, 0.95))
		draw_circle(Vector2(16, -16), 2.8, Color(0.85, 0.9, 1.0, 0.95))
	if not _emote_text.is_empty():
		_draw_emote_bubble()
	if is_following():
		draw_circle(Vector2(0, 8), 2.0, Color(0.35, 0.82, 0.95, 0.95))
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
	if is_dead():
		_action_queue.clear()
		_current_action = {}
		return
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
		AgentActions.KIND_MARK:
			_execute_mark(_current_action)
		AgentActions.KIND_FOLLOW:
			_execute_follow(_current_action)
		AgentActions.KIND_MEET:
			_execute_meet(_current_action)
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
	_snapshot_walk_sight()
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
	var origin := Vector2(-sz.x * 0.5, -20.0)
	var pad := Vector2(3.0, 2.0)
	var rect := Rect2(origin + Vector2(-pad.x, -sz.y - 1.0), sz + pad * 2.0)
	draw_rect(rect, Color(0.08, 0.08, 0.12, 0.86), true)
	draw_rect(rect, Color(1.0, 0.95, 0.7, 0.55), false, 1.0)
	draw_string(font, origin, _emote_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1.0, 0.96, 0.78))


func _draw_vital_bars() -> void:
	if not vitals.enabled():
		return
	# 精灵居中 16×16，顶边在 y=-8；三条都画在头顶上方，避免被 Sprite2D 盖住
	var origin := Vector2(-7.0, -20.0)
	if Config.vitals_bar_health():
		_draw_meter_bar(
			origin,
			vitals.health_ratio(),
			1.0,
			vitals.health_ratio(),
			2.5,
			"health",
		)
		origin.y += 4.0
	if Config.vitals_bar_energy():
		_draw_meter_bar(
			origin,
			vitals.energy_fill_of_base(),
			vitals.ceiling_fill_of_base(),
			vitals.energy_ratio(),
			3.0,
		)
		origin.y += 4.0
	if Config.vitals_bar_satiety():
		_draw_meter_bar(
			origin,
			vitals.satiety_fill_of_base(),
			clampf(vitals.satiety_ceiling / maxf(1.0, float(Config.vitals_cfg().get("base_max", 100))), 0.0, 1.0),
			vitals.satiety_ratio(),
			1.5,
			"satiety",
		)


func _draw_meter_bar(
	origin: Vector2,
	fill_of_base: float,
	ceiling_of_base: float,
	feel_ratio: float,
	height: float,
	kind: String = "energy",
) -> void:
	var width: float = 14.0
	var border := Rect2(origin, Vector2(width, height))
	draw_rect(border, Color(0.05, 0.05, 0.07, 0.9), true)
	var inner := Rect2(origin + Vector2(1.0, 0.5), Vector2(width - 2.0, height - 1.0))
	if inner.size.x <= 0.0 or inner.size.y <= 0.0:
		return
	draw_rect(inner, Color(0.18, 0.16, 0.16, 0.85), true)
	var ceil_w: float = inner.size.x * clampf(ceiling_of_base, 0.0, 1.0)
	var fill_w: float = inner.size.x * clampf(fill_of_base, 0.0, 1.0)
	var fill_color: Color
	if kind == "satiety":
		fill_color = Color(0.92, 0.55, 0.18).lerp(Color(0.95, 0.78, 0.28), clampf(feel_ratio, 0.0, 1.0))
		if feel_ratio < 0.35:
			fill_color = Color(0.82, 0.28, 0.12)
	elif kind == "health":
		if feel_ratio <= 0.0:
			fill_color = Color(0.22, 0.08, 0.08)
		elif feel_ratio < 0.35:
			fill_color = Color(0.78, 0.16, 0.18)
		else:
			fill_color = Color(0.72, 0.22, 0.28).lerp(Color(0.86, 0.32, 0.38), clampf(feel_ratio, 0.0, 1.0))
	else:
		if feel_ratio < 0.28:
			fill_color = Color(0.86, 0.2, 0.16)
		elif feel_ratio < 0.55:
			fill_color = Color(0.92, 0.78, 0.18)
		else:
			fill_color = Color(0.32, 0.82, 0.38)
	if fill_w > 0.05:
		draw_rect(Rect2(inner.position, Vector2(fill_w, inner.size.y)), fill_color, true)
	if ceil_w > 1.0 and ceil_w < inner.size.x - 0.5:
		var tick_x: float = inner.position.x + ceil_w
		draw_line(
			Vector2(tick_x, inner.position.y - 0.5),
			Vector2(tick_x, inner.position.y + inner.size.y + 0.5),
			Color(1.0, 1.0, 1.0, 0.7),
			1.0,
		)
	draw_rect(border, Color(0.02, 0.02, 0.03, 0.95), false, 1.0)


func _execute_pick_up(action: Dictionary) -> void:
	var p: Dictionary = action["params"]
	var item_id: String = AgentActions.normalize_pickup_item(str(p.get("item", "")))
	var tick: int = _clock.current_tick() if _clock else -1
	if _world == null or _world.state == null:
		_log_action(tick, "pickup", "FAILED no world state")
		_log_obs_action(AgentActions.KIND_PICK_UP, p, false, "no world state")
	elif not Config.can_carry_item(inventory, item_id):
		_log_action(tick, "pickup", "FAILED food inventory full")
		_log_obs_action(AgentActions.KIND_PICK_UP, p, false, "food inventory full")
	else:
		var batch_food: bool = Config.is_food_gather_token(item_id) or Config.item_is_food(item_id)
		var res: Dictionary = {}
		if batch_food:
			var radius: int = perception_radius() if Config.world_food_gather_in_sight() else Config.world_item_pickup_radius()
			var room: int = Config.vitals_food_inventory_max() - food_count()
			res = _world.state.try_gather_food(get_tile_position(), item_id, radius, _world, room)
			if res.get("ok", false):
				var got: Array = res.get("items", [])
				for iid in got:
					inventory.append(str(iid))
				var summary: String = ",".join(got)
				_log_action(tick, "pickup", "got %s" % summary)
				_log_obs_action(AgentActions.KIND_PICK_UP, p, true, "got %s" % summary)
			else:
				var err_g: String = str(res.get("error", "?"))
				_log_action(tick, "pickup", "FAILED %s" % err_g)
				_log_obs_action(AgentActions.KIND_PICK_UP, p, false, err_g, err_g)
		else:
			res = _world.state.try_pick_up(get_tile_position(), item_id)
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
		var fed: Player = _resolve_feed_target(on_target)
		if Config.item_is_food(item_id) and fed != null and fed.is_dead():
			_log_action(tick, "use", "FAILED target dead: %s" % on_target)
			_log_obs_action(AgentActions.KIND_USE, p, false, "target dead", on_target)
			_pump_next_action()
			return
		if not Config.item_is_usable(item_id, inventory):
			var reason: String = Config.item_unusable_reason(item_id, inventory)
			_log_action(tick, "use", "FAILED %s" % reason)
			_log_obs_action(AgentActions.KIND_USE, p, false, reason, item_id)
			_pump_next_action()
			return
		if Config.item_can_craft_campfire(item_id, inventory):
			if on_target not in ["self", "", str(agent_id)]:
				_log_action(tick, "use", "FAILED campfire only at own tile")
				_log_obs_action(AgentActions.KIND_USE, p, false, "campfire only at own tile")
				_pump_next_action()
				return
			var partner: String = Config.item_craft_partner(item_id)
			inventory.erase(item_id)
			inventory.erase(partner)
			var fire: Dictionary = {"ok": false, "error": "no world"}
			if _world != null and _world.state != null:
				fire = _world.state.light_campfire(get_tile_position(), str(agent_id), tick)
			if fire.get("ok", false):
				text = "生起篝火（用了%s和%s）" % [
					str(def.get("display_name", item_id)),
					str(Config.item_def(partner).get("display_name", partner)),
				]
				_log_action(tick, "use", text)
				_log_obs_action(AgentActions.KIND_USE, p, true, text)
			else:
				inventory.append(item_id)
				inventory.append(partner)
				var err_f: String = str(fire.get("error", "?"))
				_log_action(tick, "use", "FAILED %s" % err_f)
				_log_obs_action(AgentActions.KIND_USE, p, false, err_f, err_f)
			_pump_next_action()
			return
		if Config.item_is_food(item_id) and fed != null and fed.vitals.enabled():
			var eaten: Dictionary = fed.vitals.eat(
				float(def.get("satiety_restore", 0)),
				float(def.get("energy_restore", 0)),
			)
			if fed != self:
				text = "%s（喂给 %s）精力+%d 饱腹+%d" % [
					text, str(fed.agent_id),
					int(round(float(eaten.get("energy_delta", 0)))),
					int(round(float(eaten.get("satiety_delta", 0)))),
				]
			else:
				text = "%s 精力+%d 饱腹+%d" % [
					text,
					int(round(float(eaten.get("energy_delta", 0)))),
					int(round(float(eaten.get("satiety_delta", 0)))),
				]
			fed.queue_redraw()
		elif on_target not in ["self", str(agent_id)]:
			text = "%s (on %s)" % [text, on_target]
		if bool(def.get("consumable", false)) or Config.item_is_food(item_id):
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


func _execute_mark(action: Dictionary) -> void:
	var p: Dictionary = action["params"]
	var tick: int = _clock.current_tick() if _clock else -1
	var tile := Vector2i(int(p.get("x", 0)), int(p.get("y", 0)))
	var label: String = str(p.get("label", "")).strip_edges()
	if _world == null or _world.state == null:
		_log_action(tick, "mark", "FAILED no world state")
		_log_obs_action(AgentActions.KIND_MARK, p, false, "no world state")
		_pump_next_action()
		return
	var res: Dictionary = _world.state.place_mark(tile, label, str(agent_id), tick)
	if res.get("ok", false):
		var detail: String = "「%s」@(%d,%d)" % [str(res.get("label", label)), tile.x, tile.y]
		_log_action(tick, "mark", detail)
		_log_obs_action(AgentActions.KIND_MARK, p, true, detail)
	else:
		var err: String = str(res.get("error", "?"))
		_log_action(tick, "mark", "FAILED %s" % err)
		_log_obs_action(AgentActions.KIND_MARK, p, false, err, err)
	_pump_next_action()


func _execute_follow(action: Dictionary) -> void:
	var p: Dictionary = action["params"]
	var to_id: String = str(p.get("to", "")).strip_edges()
	var tick: int = _clock.current_tick() if _clock else -1
	if _comm == null:
		_log_action(tick, "follow", "FAILED no comm router")
		_log_obs_action(AgentActions.KIND_FOLLOW, p, false, "no comm router")
		_pump_next_action()
		return
	var other: Player = _comm.find_player(to_id)
	if other == null or other.is_dead():
		_log_action(tick, "follow", "FAILED unknown/dead %s" % to_id)
		_log_obs_action(AgentActions.KIND_FOLLOW, p, false, "unknown/dead", to_id)
		_pump_next_action()
		return
	var in_sight := false
	for seen in _comm.players_in_sight(self):
		if seen == other:
			in_sight = true
			break
	if not in_sight:
		_log_action(tick, "follow", "FAILED not in sight %s" % to_id)
		_log_obs_action(AgentActions.KIND_FOLLOW, p, false, "not in sight", to_id)
		_pump_next_action()
		return
	_follow_id = to_id
	_follow_until_tick = tick + Config.traces_follow_max_ticks()
	_snapshot_walk_sight()
	_log_action(tick, "follow", "→ %s until t%d" % [to_id, _follow_until_tick])
	_log_obs_action(AgentActions.KIND_FOLLOW, p, true, "→ %s" % to_id)
	if not _retarget_follow():
		_pump_next_action()


func _execute_meet(action: Dictionary) -> void:
	var p: Dictionary = action["params"]
	var tick: int = _clock.current_tick() if _clock else -1
	var tile := Vector2i(int(p.get("x", 0)), int(p.get("y", 0)))
	var until_tick: int = int(p.get("until_tick", 0))
	var to_id: String = str(p.get("to", "")).strip_edges()
	if until_tick <= tick:
		until_tick = tick + Config.traces_meet_default_ticks()
	if _world == null or _world.state == null:
		_log_action(tick, "meet", "FAILED no world state")
		_log_obs_action(AgentActions.KIND_MEET, p, false, "no world state")
		_pump_next_action()
		return
	var res: Dictionary = _world.state.add_meet(str(agent_id), tile, until_tick, to_id, tick)
	if res.get("ok", false):
		var who: String = to_id if not to_id.is_empty() else "大家"
		var detail: String = "约 %s 于(%d,%d) 至 t%d" % [who, tile.x, tile.y, until_tick]
		_log_action(tick, "meet", detail)
		_log_obs_action(AgentActions.KIND_MEET, p, true, detail)
		if _comm != null and not to_id.is_empty() and to_id != "broadcast":
			var other: Player = _comm.find_player(to_id)
			if other != null:
				other.receive_meet(str(agent_id), tile, until_tick, tick)
	else:
		var err: String = str(res.get("error", "?"))
		_log_action(tick, "meet", "FAILED %s" % err)
		_log_obs_action(AgentActions.KIND_MEET, p, false, err, err)
	_pump_next_action()


func _enter_sleep(until_tick: int) -> void:
	_sleep_until_tick = until_tick
	_state = State.SLEEPING
	modulate = Color(0.62, 0.64, 0.82)
	queue_redraw()


func _restore_sleep(until_tick: int) -> void:
	if until_tick <= current_tick():
		return
	_enter_sleep(until_tick)


func _become_corpse(announce: bool) -> void:
	if _state == State.DEAD:
		return
	_action_queue.clear()
	_current_path.clear()
	_path_idx = 0
	_wait_remaining = 0
	_sleep_until_tick = 0
	_walk_stuck_time = 0.0
	_current_action = {}
	_emote_text = ""
	_emote_left = 0.0
	_clear_pending_reply()
	clear_follow()
	_state = State.DEAD
	vitals.health = 0.0
	modulate = Color(0.34, 0.32, 0.32)
	queue_redraw()
	if not announce:
		return
	var tick: int = _clock.current_tick() if _clock else -1
	var text := "健康降至 0（连续未睡%d夜 连续未进食%d天）" % [
		vitals.nights_without_sleep,
		vitals.days_without_food,
	]
	_log_action(tick, "die", text)
	_log_obs_action("DIE", {}, true, text)
	died.emit()


func _on_clock_tick(_tick_index: int) -> void:
	if is_dead():
		return
	if is_following() and _follow_until_tick > 0 and current_tick() >= _follow_until_tick:
		clear_follow()
	_tick_dwell()
	if _clock != null:
		var p: String = _clock.phase()
		if p != _last_phase:
			_last_phase = p
			_last_observation_tick = -1
	var still_sleeping: bool = (
		_state == State.SLEEPING
		and _clock != null
		and _clock.current_tick() < _sleep_until_tick
	)
	vitals.on_tick(
		_clock.day_index() if _clock != null else 0,
		_clock.phase() if _clock != null else "day",
		still_sleeping,
		_state == State.WALKING,
		near_campfire(),
		_storm_energy_scale(),
	)
	if vitals.enabled():
		queue_redraw()
	if vitals.is_deceased():
		_become_corpse(true)
		return
	if is_following() and _state == State.IDLE:
		_retarget_follow()
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


func _tick_dwell() -> void:
	var tile: Vector2i = get_tile_position()
	var radius: int = Config.exploration_dwell_radius()
	if abs(tile.x - _dwell_anchor.x) <= radius and abs(tile.y - _dwell_anchor.y) <= radius:
		_dwell_ticks += 1
	else:
		_dwell_anchor = tile
		_dwell_ticks = 0


func cached_frontier_tiles() -> Array:
	var t: int = current_tick()
	if t == _frontier_cache_tick:
		return _frontier_cache
	_frontier_cache_tick = t
	_frontier_cache = AgentActions.frontier_tiles(
		_world,
		exploration,
		get_tile_position(),
		Config.exploration_frontier_prompt_max(),
	)
	return _frontier_cache


func _finish_idle() -> void:
	if is_dead():
		return
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


func _resolve_feed_target(on_target: String) -> Player:
	if on_target.is_empty() or on_target in ["self", str(agent_id)]:
		return self
	if _comm == null:
		return self
	for other in _comm.players_in_perception(self):
		if str(other.agent_id) == on_target:
			return other
	return self


func receive_say(from_id: String, text: String, _tone: String, tick: int) -> void:
	if is_dead():
		return
	_heard_messages.append({"from": from_id, "text": text, "tick": tick})
	if _heard_messages.size() > 6:
		_heard_messages.pop_front()
	_pending_reply_from = from_id
	_pending_reply_text = text
	_pending_reply_tick = tick
	_log_action(tick, "heard", "%s: %s" % [from_id, text])


func receive_emote(from_id: String, emoji: String, tick: int) -> void:
	if is_dead():
		return
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


func can_accept_item(item_id: String) -> bool:
	if is_dead():
		return false
	return Config.can_carry_item(inventory, item_id)


func food_count() -> int:
	return Config.food_count_in(inventory)


func can_relieve_vitals_in_place() -> bool:
	if not vitals.enabled() or is_dead():
		return false
	var hungry_or_tired: bool = vitals.is_hungry() or vitals.is_tired()
	if hungry_or_tired and food_count() > 0:
		return true
	if not vitals.is_tired():
		return false
	if _clock == null or not _clock.time_enabled():
		return false
	var phase: String = _clock.phase()
	return phase == "dusk" or phase == "night"


func _dedupe_queued_moves() -> void:
	var kept: Array = []
	var last_move: Dictionary = {}
	for raw in _action_queue:
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var action: Dictionary = raw
		if str(action.get("kind", "")) == AgentActions.KIND_MOVE_TO:
			last_move = action
			continue
		kept.append(action)
	if not last_move.is_empty():
		kept.append(last_move)
	_action_queue = kept


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
		if is_following() and _retarget_follow():
			return
		_pump_next_action()
		return
	var target: Vector2 = _current_path[_path_idx]
	var dir: Vector2 = (target - global_position)
	var dist: float = dir.length()
	if dist < 1.0:
		_path_idx += 1
		return
	dir = dir / dist
	velocity = dir * move_speed_px * vitals.move_speed_scale()
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
	exploration.update_observer(Vector2i(cx, cy), r, _world, t)
	_frontier_cache_tick = -999
	var origin := Vector2i(cx, cy)
	var terrain_text := _observation_terrain_summary(origin, r)
	var living_parts: PackedStringArray = PackedStringArray()
	var corpse_parts: PackedStringArray = PackedStringArray()
	if _comm != null:
		for p in _comm.players_in_perception(self):
			var pt: Vector2i = p.get_tile_position()
			var extra := ""
			if p.is_dead():
				corpse_parts.append("%s@(%d,%d) 已死亡" % [str(p.agent_id), pt.x, pt.y])
				continue
			if p.is_sleeping():
				extra = " 入睡"
			if p.is_following():
				extra += " 跟随%s" % p.following_id()
			if p.vitals.enabled():
				if p.vitals.is_tired():
					extra += " 疲惫"
				if p.vitals.is_hungry():
					extra += " 饥饿"
				if p.vitals.is_frail():
					extra += " 虚弱"
			var face: String = p.current_emote()
			if not face.is_empty():
				extra += " %s" % face
			living_parts.append("%s@(%d,%d)%s" % [str(p.agent_id), pt.x, pt.y, extra])
	var lines: PackedStringArray = PackedStringArray()
	lines.append("区域=%s" % region_name)
	lines.append("地形: %s" % terrain_text)
	var landmarks: Array = []
	if _world != null and _world.state != null:
		landmarks = _world.state.nearest_landmarks(
			origin,
			Config.observation_landmark_max(),
			Config.observation_landmark_max_dist(),
		)
	if landmarks.size() > 0:
		var mark_bits: PackedStringArray = PackedStringArray()
		for lm in landmarks:
			var ltile: Vector2i = lm.get("tile", Vector2i.ZERO)
			mark_bits.append("%s(%d,%d)距%d格" % [
				str(lm.get("name", "")),
				ltile.x,
				ltile.y,
				int(lm.get("dist", 0)),
			])
		lines.append("地标: %s" % " ".join(mark_bits))
	if _world != null and _world.state != null:
		var named: PackedStringArray = PackedStringArray()
		for mark in _world.state.marks_in_sight(origin, r, _world):
			var mt: Vector2i = mark.get("tile", Vector2i.ZERO)
			named.append("「%s」@(%d,%d) by %s" % [
				str(mark.get("label", "")),
				mt.x,
				mt.y,
				str(mark.get("by", "")),
			])
		if named.size() > 0:
			lines.append("铭刻: %s" % ", ".join(named))
		var fires: PackedStringArray = PackedStringArray()
		for fire in _world.state.all_campfires():
			var ft: Vector2i = fire.get("tile", Vector2i.ZERO)
			var dx: int = ft.x - origin.x
			var dy: int = ft.y - origin.y
			if dx * dx + dy * dy > r * r:
				continue
			if not _world.has_line_of_sight(origin, ft):
				continue
			fires.append("篝火@(%d,%d) %s生" % [ft.x, ft.y, str(fire.get("by", ""))])
		if fires.size() > 0:
			lines.append("篝火: %s" % ", ".join(fires))
		var meets: PackedStringArray = PackedStringArray()
		for meet in _world.state.active_meets():
			var who: String = str(meet.get("to", ""))
			if who.is_empty():
				who = "大家"
			meets.append("%s约%s于(%d,%d)至t%d" % [
				str(meet.get("by", "")),
				who,
				int(meet.get("x", 0)),
				int(meet.get("y", 0)),
				int(meet.get("until_tick", 0)),
			])
		if meets.size() > 0:
			lines.append("约定: %s" % ", ".join(meets))
	if living_parts.size() > 0:
		lines.append("活人: %s" % ", ".join(living_parts))
	else:
		lines.append("活人: 无")
	if corpse_parts.size() > 0:
		lines.append("尸体: %s" % ", ".join(corpse_parts))
	var food_parts: PackedStringArray = PackedStringArray()
	var other_parts: PackedStringArray = PackedStringArray()
	if _world != null and _world.state != null:
		for item in _world.state.items_in_sight(origin, r, _world):
			var item_tile: Vector2i = item.get("tile", Vector2i.ZERO)
			var iid: String = str(item.get("item_id", "?"))
			var label: String = "%s@(%d,%d)" % [iid, item_tile.x, item_tile.y]
			if Config.item_is_food(iid):
				food_parts.append(label)
			else:
				other_parts.append(label)
	if food_parts.size() > 0:
		lines.append("食物: %s" % ", ".join(food_parts))
	if other_parts.size() > 0:
		lines.append("其它物品: %s" % ", ".join(other_parts))
	if _world.events != null:
		var event_lines: PackedStringArray = _world.events.lines_for_tile(origin)
		if event_lines.size() > 0:
			lines.append("事件: %s" % event_lines[0])
	var explored_n: int = exploration.explored_count()
	var frontiers: Array = cached_frontier_tiles()
	var frontier_n: int = mini(frontiers.size(), Config.observation_frontier_max())
	if frontier_n > 0:
		var bits: PackedStringArray = PackedStringArray()
		for i in frontier_n:
			var edge: Vector2i = frontiers[i]
			bits.append("%s(%d,%d)" % [AgentActions.compass_name(origin, edge), edge.x, edge.y])
		lines.append("已探索%d格 未探索: %s" % [explored_n, ", ".join(bits)])
	else:
		lines.append("已探索%d格 附近无未探索可走边界" % explored_n)
	if _dwell_ticks >= Config.exploration_dwell_hint_ticks():
		lines.append("已在这片熟悉区域停留%d tick" % _dwell_ticks)
	var heard := get_recent_heard_lines(2)
	if heard.size() > 0:
		lines.append("听到: " + "; ".join(heard))
	var emotes := get_recent_emote_lines(2)
	if emotes.size() > 0:
		lines.append("表情: " + "; ".join(emotes))
	_observation_text = " | ".join(lines)
	if _clock != null and _clock.time_enabled():
		_observation_text = "%s 下次黎明t%d | %s" % [
			_clock.format_phase_clock(),
			_clock.next_dawn_tick(),
			_observation_text,
		]


func _observation_terrain_summary(origin: Vector2i, radius: int) -> String:
	var counts: Dictionary = {}
	var total: int = 0
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy > radius * radius:
				continue
			var tile := Vector2i(origin.x + dx, origin.y + dy)
			if not _world.has_line_of_sight(origin, tile):
				continue
			var name: String = _tile_name(_world.tile_at(Vector2(tile.x * TILE_SIZE, tile.y * TILE_SIZE)))
			counts[name] = int(counts.get(name, 0)) + 1
			total += 1
	if total <= 0 or counts.is_empty():
		return "（空）"
	var ranked: Array = []
	for name in counts.keys():
		ranked.append({"name": str(name), "n": int(counts[name])})
	ranked.sort_custom(func(a, b): return int(a["n"]) > int(b["n"]))
	var majority: String = str(ranked[0]["name"])
	var extras: PackedStringArray = PackedStringArray()
	for i in range(1, ranked.size()):
		if extras.size() >= 3:
			break
		extras.append(str(ranked[i]["name"]))
	if extras.is_empty():
		return "%s为主" % majority
	return "%s为主，可见%s" % [majority, "、".join(extras)]


func _snapshot_walk_sight() -> void:
	_walk_sight_ids.clear()
	_walk_vitals_nudge_done = false
	if _comm == null:
		return
	for p in _comm.players_in_sight(self):
		_walk_sight_ids[str(p.agent_id)] = true


func walk_new_sight_living() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if _comm == null:
		return out
	for p in _comm.players_in_sight(self):
		var id: String = str(p.agent_id)
		if not _walk_sight_ids.has(id):
			out.append(id)
	return out


func walk_vitals_nudge_done() -> bool:
	return _walk_vitals_nudge_done


func mark_walk_vitals_nudge() -> void:
	_walk_vitals_nudge_done = true


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
	if _state == State.DEAD:
		state_zh = "已死亡"
	elif _state == State.WALKING:
		state_zh = "行走"
	elif _state == State.WAITING:
		state_zh = "等待"
	elif _state == State.SLEEPING:
		state_zh = "睡觉余%d" % maxi(0, _sleep_until_tick - current_tick())
	if is_following():
		state_zh += " 跟随%s" % _follow_id
	var time_s := ""
	if _clock != null and _clock.time_enabled():
		time_s = "  %s" % _clock.format_phase_clock()
	var vitals_s := ""
	if vitals.enabled():
		vitals_s = "  %s  食物%d/%d" % [
			vitals.format_status(),
			food_count(),
			Config.vitals_food_inventory_max(),
		]
	return "角色=%s  状态=%s  队列=%d  背包=%s  坐标=(%d,%d)  地形=%s%s%s" % [
		str(agent_id),
		state_zh,
		queue_n,
		_inventory_summary(),
		tile_x,
		tile_y,
		_tile_name(t),
		time_s,
		vitals_s,
	]


func _inventory_summary() -> String:
	if inventory.is_empty():
		return "空"
	return ",".join(inventory)


func get_nearby_item_lines() -> PackedStringArray:
	var lines: PackedStringArray = []
	if _world == null or _world.state == null:
		return lines
	for item in _world.state.items_in_sight(get_tile_position(), perception_radius(), _world):
		var t: Vector2i = item.get("tile", Vector2i.ZERO)
		var iid: String = str(item.get("item_id", ""))
		var gather: String = ""
		if Config.item_is_food(iid) and Config.world_food_gather_in_sight():
			gather = " 一次可收完视野内同类"
		lines.append("%s（%s）在 (%d,%d)%s%s" % [
			iid,
			str(item.get("display_name", "")),
			t.x,
			t.y,
			" 可食用" if Config.item_is_food(iid) else "",
			gather,
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
