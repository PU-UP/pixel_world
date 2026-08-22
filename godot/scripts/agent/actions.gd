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
const KIND_SLEEP     := "SLEEP"
const KIND_WAIT      := "WAIT"

# P2: MOVE_TO | P5: SAY
const IMPLEMENTED_KINDS: Array[String] = [KIND_MOVE_TO, KIND_SAY]

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
	KIND_SLEEP:    0,    # 实际 = until_tick - now
	KIND_WAIT:     0,    # 实际 = ticks
}

const MOVE_TICKS_PER_TILE: int = 1   # 每走 1 瓦片消耗 1 tick

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

## 调试: action -> 字符串 (勿命名为 to_string, 会与 Object 内置方法冲突)
static func format_action(action: Dictionary) -> String:
	if not action.has("kind"):
		return "(invalid action: no kind)"
	return "[%s] %s" % [action["kind"], str(action.get("params", {}))]
