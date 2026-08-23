class_name AgentActions
##
## 行动原语 (Action Primitives) 定义 + schema 校验
##
## 详见 AGENTS.md §4 与 docs/action-schema.md
## 一次 tick 只能选一个原语; 一次决策可以包含多个原语 (P3 决定后由 executor 排队)
##

# ------------------------------------------------------------------
# 原语常量
# ------------------------------------------------------------------
const KIND_MOVE_TO   := "MOVE_TO"
const KIND_SAY       := "SAY"
const KIND_EMOTE     := "EMOTE"
const KIND_OBSERVE   := "OBSERVE"
const KIND_PICK_UP   := "PICK_UP"
const KIND_DROP      := "DROP"
const KIND_USE       := "USE"
const KIND_GIVE      := "GIVE"
const KIND_SHARE_MAP := "SHARE_MAP"
const KIND_SLEEP     := "SLEEP"
const KIND_WAIT      := "WAIT"

# P2: MOVE_TO | P5: SAY | P7: PICK_UP, DROP, OBSERVE
const IMPLEMENTED_KINDS: Array[String] = [
	KIND_MOVE_TO, KIND_SAY, KIND_PICK_UP, KIND_DROP, KIND_OBSERVE, KIND_USE, KIND_GIVE, KIND_SHARE_MAP,
]

# ------------------------------------------------------------------
# Schema 定义: 每个原语需要哪些字段, 以及类型
# 简化版: 只列必填字段, 校验函数做 "字段存在" 检查
# ------------------------------------------------------------------
const SCHEMAS: Dictionary = {
	KIND_MOVE_TO: {
		"required": ["x", "y"],
		"types":    {"x": TYPE_INT, "y": TYPE_INT},
		"desc":     "Move to tile (x, y) via A* pathfinding",
	},
	KIND_SAY: {
		"required": ["to", "text"],
		"types":    {"to": TYPE_STRING, "text": TYPE_STRING},
		"desc":     "Say text to a specific agent or 'broadcast'",
	},
	KIND_EMOTE: {
		"required": ["emoji"],
		"types":    {"emoji": TYPE_STRING},
		"desc":     "Display an emoji/emote",
	},
	KIND_OBSERVE: {
		"required": ["target"],
		"types":    {"target": TYPE_STRING},
		"desc":     "Actively observe a target (get more details)",
	},
	KIND_PICK_UP: {
		"required": ["item"],
		"types":    {"item": TYPE_STRING},
		"desc":     "Pick up an item",
	},
	KIND_DROP: {
		"required": ["item"],
		"types":    {"item": TYPE_STRING},
		"desc":     "Drop an item",
	},
	KIND_USE: {
		"required": ["item", "on"],
		"types":    {"item": TYPE_STRING, "on": TYPE_STRING},
		"desc":     "Use an item on a target",
	},
	KIND_GIVE: {
		"required": ["item", "to"],
		"types":    {"item": TYPE_STRING, "to": TYPE_STRING},
		"desc":     "Give an item to another agent",
	},
	KIND_SHARE_MAP: {
		"required": ["to"],
		"types":    {"to": TYPE_STRING},
		"desc":     "Offer to share explored map with another agent (mutual SHARE_MAP merges gray areas)",
	},
	KIND_SLEEP: {
		"required": ["until_tick"],
		"types":    {"until_tick": TYPE_INT},
		"desc":     "Sleep until the given tick",
	},
	KIND_WAIT: {
		"required": ["ticks"],
		"types":    {"ticks": TYPE_INT},
		"desc":     "Wait in place for N ticks",
	},
}

# ------------------------------------------------------------------
# tick 消耗(基础值, MOVE_TO 实际是 path.length)
# ------------------------------------------------------------------
const TICK_COST_BASE: Dictionary = {
	KIND_MOVE_TO:  0,    # 实际 = path_length * MOVE_TICKS_PER_TILE
	KIND_SAY:      1,
	KIND_EMOTE:    0,
	KIND_OBSERVE:  1,
	KIND_PICK_UP:  1,
	KIND_DROP:     0,
	KIND_USE:      1,
	KIND_GIVE:     1,
	KIND_SHARE_MAP: 1,
	KIND_SLEEP:    0,    # 实际 = until_tick - now
	KIND_WAIT:     0,    # 实际 = ticks
}

const MOVE_TICKS_PER_TILE: int = 1   # 每走 1 瓦片消耗 1 tick

const AStarPathfinder = preload("res://scripts/world/pathfinding.gd")

# ------------------------------------------------------------------
# 校验
# ------------------------------------------------------------------
## 返回 {ok: bool, error: String}
static func validate(action: Dictionary) -> Dictionary:
	if not action.has("kind"):
		return {"ok": false, "error": "missing 'kind' field"}
	if not action.has("params"):
		return {"ok": false, "error": "missing 'params' field"}
	var kind: String = action["kind"]
	if not SCHEMAS.has(kind):
		return {"ok": false, "error": "unknown kind: %s" % kind}
	var schema: Dictionary = SCHEMAS[kind]
	var params: Dictionary = action["params"]
	# 必填字段
	for f in schema["required"]:
		if not params.has(f):
			return {"ok": false, "error": "missing param '%s' for %s" % [f, kind]}
	# 类型检查（LLM 常返回 float 坐标，自动转为 int）
	for f in schema["types"]:
		if not params.has(f):
			continue
		var expected: int = schema["types"][f]
		var actual_type: int = typeof(params[f])
		if actual_type != expected:
			if expected == TYPE_INT and actual_type == TYPE_FLOAT:
				params[f] = int(params[f])
			elif expected == TYPE_STRING and actual_type in [TYPE_INT, TYPE_FLOAT, TYPE_BOOL]:
				params[f] = str(params[f])
			else:
				return {"ok": false, "error": "param '%s' type mismatch (want %d got %d)" % [f, expected, actual_type]}
	return {"ok": true, "error": ""}


## 结合世界状态的上下文校验 — 返回 {ok, error, hint}
## hint: move_closer | unreachable
static func validate_in_context(action: Dictionary, ctx: Dictionary) -> Dictionary:
	var base: Dictionary = validate(action)
	if not base["ok"]:
		return {"ok": false, "error": base["error"], "hint": ""}
	var kind: String = action["kind"]
	var params: Dictionary = action["params"]
	match kind:
		KIND_SAY:
			var to_s: String = str(params.get("to", "")).strip_edges()
			if to_s == "broadcast":
				return {"ok": true, "error": "", "hint": ""}
			if _looks_like_tick_id(to_s):
				return {"ok": false, "error": "unknown agent: %s" % to_s, "hint": ""}
			var audio_ids: Array = ctx.get("audio_agent_ids", [])
			if _contains_id(audio_ids, to_s):
				return {"ok": true, "error": "", "hint": ""}
			var perception_ids: Array = ctx.get("perception_agent_ids", [])
			if _contains_id(perception_ids, to_s):
				return {"ok": false, "error": "target out of audio range", "hint": "move_closer"}
			var all_ids: Array = ctx.get("all_agent_ids", [])
			if _contains_id(all_ids, to_s):
				return {
					"ok": false,
					"error": "agent not in range: %s" % to_s,
					"hint": "approach_agent",
					"approach_id": to_s,
				}
			return {"ok": false, "error": "unknown agent: %s" % to_s, "hint": ""}
		KIND_OBSERVE:
			var target: String = str(params.get("target", "")).strip_edges()
			if target.is_empty():
				return {"ok": false, "error": "empty observe target", "hint": ""}
			var observe_agents: Array = ctx.get("perception_agent_ids", [])
			var observe_items: Array = ctx.get("ground_item_ids", [])
			if _contains_id(observe_agents, target) or _contains_id(observe_items, target):
				return {"ok": true, "error": "", "hint": ""}
			var all_obs: Array = ctx.get("all_agent_ids", [])
			if _contains_id(all_obs, target):
				return {
					"ok": false,
					"error": "agent not in range: %s" % target,
					"hint": "approach_agent",
					"approach_id": target,
				}
			return {"ok": false, "error": "unknown/range target: %s" % target, "hint": ""}
		KIND_MOVE_TO:
			var world = ctx.get("world", null)
			var start: Vector2i = ctx.get("agent_tile", Vector2i.ZERO)
			var goal := Vector2i(int(params.get("x", 0)), int(params.get("y", 0)))
			if world == null:
				return {"ok": true, "error": "", "hint": ""}
			if goal == start:
				return {"ok": false, "error": "already at target", "hint": "already_there"}
			var blocked: Array = ctx.get("blocked_move_tiles", [])
			if _tile_key(goal) in blocked:
				var snap_blocked: Dictionary = resolve_move_goal(world, start, goal)
				if snap_blocked.get("ok", false):
					return {
						"ok": false,
						"error": "blocked unwalkable (%d, %d)" % [goal.x, goal.y],
						"hint": "snap_move",
						"snap_tile": snap_blocked.get("tile", goal),
					}
			var resolved: Dictionary = resolve_move_goal(world, start, goal)
			if resolved.get("ok", false):
				var resolved_tile: Vector2i = resolved.get("tile", goal)
				if resolved_tile == goal:
					return {"ok": true, "error": "", "hint": ""}
				return {
					"ok": false,
					"error": "unwalkable tile (%d, %d)" % [goal.x, goal.y],
					"hint": "snap_move",
					"snap_tile": resolved_tile,
				}
			return {"ok": false, "error": "path empty", "hint": "unreachable"}
		KIND_PICK_UP:
			var item_id: String = str(params.get("item", "")).strip_edges()
			var pickup_ids: Array = ctx.get("pickup_item_ids", [])
			if _contains_id(pickup_ids, item_id):
				return {"ok": true, "error": "", "hint": ""}
			return {"ok": false, "error": "item not in pickup range: %s" % item_id, "hint": ""}
		KIND_GIVE:
			var to_give: String = str(params.get("to", "")).strip_edges()
			var item_g: String = str(params.get("item", "")).strip_edges()
			if _looks_like_tick_id(to_give):
				return {"ok": false, "error": "unknown agent: %s" % to_give, "hint": ""}
			var audio_g: Array = ctx.get("audio_agent_ids", [])
			if _contains_id(audio_g, to_give):
				var inv: Array = ctx.get("inventory", [])
				if not _contains_id(inv, item_g):
					return {"ok": false, "error": "not carrying item: %s" % item_g, "hint": ""}
				return {"ok": true, "error": "", "hint": ""}
			var perception_g: Array = ctx.get("perception_agent_ids", [])
			if _contains_id(perception_g, to_give):
				return {"ok": false, "error": "target out of audio range", "hint": "move_closer"}
			var all_g: Array = ctx.get("all_agent_ids", [])
			if _contains_id(all_g, to_give):
				return {
					"ok": false,
					"error": "agent not in range: %s" % to_give,
					"hint": "approach_agent",
					"approach_id": to_give,
				}
			return {"ok": false, "error": "unknown agent: %s" % to_give, "hint": ""}
		KIND_SHARE_MAP:
			var to_share: String = str(params.get("to", "")).strip_edges()
			if _looks_like_tick_id(to_share):
				return {"ok": false, "error": "unknown agent: %s" % to_share, "hint": ""}
			var audio_s: Array = ctx.get("audio_agent_ids", [])
			if _contains_id(audio_s, to_share):
				return {"ok": true, "error": "", "hint": ""}
			var perception_s: Array = ctx.get("perception_agent_ids", [])
			if _contains_id(perception_s, to_share):
				return {"ok": false, "error": "target out of audio range", "hint": "move_closer"}
			var all_s: Array = ctx.get("all_agent_ids", [])
			if _contains_id(all_s, to_share):
				return {
					"ok": false,
					"error": "agent not in range: %s" % to_share,
					"hint": "approach_agent",
					"approach_id": to_share,
				}
			return {"ok": false, "error": "unknown agent: %s" % to_share, "hint": ""}
		KIND_DROP, KIND_USE:
			var inv_d: Array = ctx.get("inventory", [])
			var need_item: String = str(params.get("item", "")).strip_edges()
			if not _contains_id(inv_d, need_item):
				return {"ok": false, "error": "not carrying item: %s" % need_item, "hint": ""}
			return {"ok": true, "error": "", "hint": ""}
		_:
			return {"ok": true, "error": "", "hint": ""}


static func build_context(player: Player, comm, world) -> Dictionary:
	var perception_ids: PackedStringArray = PackedStringArray()
	var audio_ids: PackedStringArray = PackedStringArray()
	var ground_item_ids: PackedStringArray = PackedStringArray()
	var pickup_item_ids: PackedStringArray = PackedStringArray()
	var agent_tile: Vector2i = player.get_tile_position()
	var all_agent_ids: PackedStringArray = PackedStringArray()
	if comm != null:
		for p in comm.players_in_perception(player):
			perception_ids.append(str(p.agent_id))
		for p in comm.players_in_audio(player):
			audio_ids.append(str(p.agent_id))
		for p in comm.all_players():
			if p != player:
				all_agent_ids.append(str(p.agent_id))
	if world != null and world.state != null:
		var obs_r: int = player.observation_radius_tiles
		var pick_r: int = Config.world_item_pickup_radius()
		for item in world.state.items_near(agent_tile, obs_r + 1):
			var iid: String = str(item.get("item_id", ""))
			if not iid.is_empty():
				ground_item_ids.append(iid)
		for item in world.state.items_near(agent_tile, pick_r):
			var pid: String = str(item.get("item_id", ""))
			if not pid.is_empty():
				pickup_item_ids.append(pid)
	return {
		"perception_agent_ids": perception_ids,
		"audio_agent_ids": audio_ids,
		"all_agent_ids": all_agent_ids,
		"ground_item_ids": ground_item_ids,
		"pickup_item_ids": pickup_item_ids,
		"inventory": player.inventory.duplicate(),
		"agent_tile": agent_tile,
		"world": world,
		"blocked_move_tiles": [],
	}


## 将 MOVE_TO 目标修正为可达的最近可走格（山地/水域旁自动吸附）
static func resolve_move_goal(world, start: Vector2i, goal: Vector2i) -> Dictionary:
	if world == null:
		return {"ok": false}
	if world.is_walkable_tile(goal):
		var direct: Array = AStarPathfinder.find_path(world, start, goal)
		if not direct.is_empty():
			return {"ok": true, "tile": goal, "snapped": false}
	var best: Vector2i = Vector2i(-1, -1)
	var best_ring: int = 9999
	for ring in range(1, 7):
		for dx in range(-ring, ring + 1):
			for dy in range(-ring, ring + 1):
				if maxi(abs(dx), abs(dy)) != ring:
					continue
				var t: Vector2i = goal + Vector2i(dx, dy)
				if not world.is_walkable_tile(t):
					continue
				var path: Array = AStarPathfinder.find_path(world, start, t)
				if path.is_empty():
					continue
				if ring < best_ring:
					best_ring = ring
					best = t
		if best != Vector2i(-1, -1):
			return {"ok": true, "tile": best, "snapped": true, "from": goal}
	return {"ok": false}


static func nearby_walkable_tiles(world, center: Vector2i, radius: int = 2) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if world == null:
		return out
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var t: Vector2i = center + Vector2i(dx, dy)
			if world.is_walkable_tile(t):
				out.append("(%d,%d)" % [t.x, t.y])
	return out


static func _tile_key(tile: Vector2i) -> String:
	return "%d,%d" % [tile.x, tile.y]


static func _contains_id(ids: Array, id: String) -> bool:
	var key := id.strip_edges()
	if key.is_empty():
		return false
	for entry in ids:
		if str(entry).strip_edges() == key:
			return true
	return false


static func _looks_like_tick_id(s: String) -> bool:
	if s.length() < 2:
		return false
	return s[0].to_lower() == "t" and s.substr(1).is_valid_int()


## 计算一个 action 的总 tick 消耗
static func tick_cost(action: Dictionary, path_length: int = 1) -> int:
	var kind: String = action.get("kind", "")
	match kind:
		KIND_MOVE_TO:
			return max(1, path_length) * MOVE_TICKS_PER_TILE
		KIND_SLEEP:
			return max(1, int(action["params"].get("until_tick", 1)) - int(action.get("now_tick", 0)))
		KIND_WAIT:
			return max(1, int(action["params"].get("ticks", 1)))
		_:
			return int(TICK_COST_BASE.get(kind, 1))

## 工厂: 生成 MOVE_TO action
static func make_move_to(x: int, y: int) -> Dictionary:
	return {"kind": KIND_MOVE_TO, "params": {"x": x, "y": y}}


static func make_share_map(to_agent_id: String) -> Dictionary:
	return {"kind": KIND_SHARE_MAP, "params": {"to": to_agent_id}}


## 调试: action -> 字符串 (勿命名为 to_string, 会与 Object 内置方法冲突)
static func format_action(action: Dictionary) -> String:
	if not action.has("kind"):
		return "(invalid action: no kind)"
	return "[%s] %s" % [action["kind"], str(action.get("params", {}))]
