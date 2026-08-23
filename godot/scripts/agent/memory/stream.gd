extends Node
class_name MemoryStream
##
## 记忆流 — append / retrieve / decay, 每个 agent 一个实例
##

signal memory_added(memory: Dictionary)

const MemoryStore = preload("res://scripts/agent/memory/store.gd")
const MemoryImportance = preload("res://scripts/agent/memory/importance.gd")

var _store: MemoryStore = MemoryStore.new()
var _event_count: int = 0
var _last_decay_tick: int = 0


func open(agent_id: String) -> void:
	_store.open(agent_id)


func append_event(
	category: String,
	text: String,
	tick: int,
	emotional_intensity: float = 0.0,
	social_relevance: float = 0.0,
	goal_relevance: float = 0.0,
) -> int:
	var cfg := Config.memory_cfg()
	var window: int = int(Config.memory_retrieval_cfg().get("time_window_ticks", 600))
	var importance := MemoryImportance.score(
		category, 0, window,
		emotional_intensity, social_relevance, goal_relevance
	)
	var mem := {
		"agent_id": _store.agent_id,
		"tick": tick,
		"category": category,
		"text": text,
		"importance": importance,
	}
	var id := _store.append(mem)
	_event_count += 1
	memory_added.emit(mem)
	return id


func retrieve_for_query(query: String, current_tick: int) -> Array:
	var cfg := Config.memory_retrieval_cfg()
	var k: int = int(cfg.get("top_k", 8))
	return _store.retrieve(query, k, current_tick, cfg)


func get_recent(limit: int) -> Array:
	return _store.get_recent(limit)


func get_reflections(limit: int) -> Array:
	return _store.get_by_category("reflection", limit)


func latest_reflection_summary() -> String:
	return _store.latest_reflection_summary()


func event_count() -> int:
	return _event_count


func reset_event_count() -> void:
	_event_count = 0


func wipe() -> void:
	_event_count = 0
	_last_decay_tick = 0
	_store.wipe()


func maybe_decay(current_tick: int) -> void:
	var cfg := Config.memory_cfg()
	var interval: int = int(cfg.get("decay_interval_ticks", 50))
	if current_tick - _last_decay_tick < interval:
		return
	_last_decay_tick = current_tick
	_store.apply_decay(current_tick, cfg)


func format_for_hud(limit: int, agent_label: String = "") -> String:
	var hud_cfg: Dictionary = Config.memory_cfg().get("hud", {})
	var allowed: Array = hud_cfg.get("categories", ["action", "action_failed", "reflection", "plan"])
	var scan: int = mini(limit * 5, _store.count())
	var recent := get_recent(scan)
	if recent.is_empty():
		return "  （空）"
	var prefix := "%s " % agent_label if not agent_label.is_empty() else ""
	var lines: PackedStringArray = []
	for mem in recent:
		var cat: String = str(mem.get("category", "?"))
		if not cat in allowed:
			continue
		var cat_zh: String = _category_zh(cat)
		var body: String = str(mem.get("text", ""))
		if body.length() > 100:
			body = body.substr(0, 99) + "…"
		lines.append(
			"  %st%-4d  %-4s  %.2f  %s" % [
				prefix,
				int(mem.get("tick", -1)),
				cat_zh,
				float(mem.get("importance", 0.0)),
				body,
			]
		)
	if lines.is_empty():
		return "  （空）"
	if lines.size() > limit:
		return "\n".join(lines.slice(lines.size() - limit, lines.size()))
	return "\n".join(lines)


static func _category_zh(category: String) -> String:
	match category:
		"decision": return "决策"
		"observation": return "观察"
		"action": return "行动"
		"action_failed": return "失败"
		"plan": return "计划"
		"reflection": return "反思"
		_: return category
