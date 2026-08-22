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


func maybe_decay(current_tick: int) -> void:
	var cfg := Config.memory_cfg()
	var interval: int = int(cfg.get("decay_interval_ticks", 50))
	if current_tick - _last_decay_tick < interval:
		return
	_last_decay_tick = current_tick
	_store.apply_decay(current_tick, cfg)


func format_for_hud(limit: int) -> String:
	var recent := get_recent(limit)
	if recent.is_empty():
		return "  (empty)"
	var lines: PackedStringArray = []
	for mem in recent:
		lines.append(
			"  t%-4d  %-10s  imp=%.2f  %s" % [
				int(mem.get("tick", -1)),
				str(mem.get("category", "?")),
				float(mem.get("importance", 0.0)),
				str(mem.get("text", "")).substr(0, 80),
			]
		)
	return "\n".join(lines)
