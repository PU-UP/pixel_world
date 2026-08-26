class_name MemoryStore
##
## 记忆持久化 — JSON 文件 (data/memory/{agent_id}.json) + 本地哈希向量
##

const MemoryImportance = preload("res://scripts/agent/memory/importance.gd")
const MemoryEmbed = preload("res://scripts/agent/memory/embed.gd")

var agent_id: String = ""
var _path: String = ""
var _next_id: int = 1
var _memories: Array = []


func open(for_agent_id: String) -> void:
	agent_id = for_agent_id
	var dir := Config.repo_root().path_join("data/memory")
	DirAccess.make_dir_recursive_absolute(dir)
	_path = dir.path_join("%s.json" % agent_id)
	_load()


func wipe() -> void:
	_memories.clear()
	_next_id = 1
	if not _path.is_empty() and FileAccess.file_exists(_path):
		DirAccess.remove_absolute(_path)


func append(entry: Dictionary) -> int:
	var mem := entry.duplicate(true)
	mem["id"] = _next_id
	_next_id += 1
	if not mem.has("tick"):
		mem["tick"] = 0
	if not mem.has("category"):
		mem["category"] = "ambient"
	if not mem.has("text"):
		mem["text"] = ""
	if not mem.has("importance"):
		mem["importance"] = MemoryImportance.base_for_category(str(mem["category"]))
	_ensure_embedding(mem)
	_memories.append(mem)
	_save()
	return int(mem["id"])


func get_recent(limit: int) -> Array:
	var n := mini(limit, _memories.size())
	if n <= 0:
		return []
	return _memories.slice(_memories.size() - n, _memories.size())


func get_by_category(category: String, limit: int) -> Array:
	var out: Array = []
	for i in range(_memories.size() - 1, -1, -1):
		var mem: Dictionary = _memories[i]
		if str(mem.get("category", "")) == category:
			out.append(mem)
			if out.size() >= limit:
				break
	return out


func count() -> int:
	return _memories.size()


func retrieve(query: String, k: int, current_tick: int, cfg: Dictionary) -> Array:
	var time_window: int = int(cfg.get("time_window_ticks", 600))
	var w_sim: float = float(cfg.get("similarity_weight", 0.7))
	var w_rec: float = float(cfg.get("recency_weight", 0.3))
	var w_imp: float = float(cfg.get("importance_weight", 0.2))
	var drop_future: bool = bool(cfg.get("drop_future_ticks", true))
	var collapse: Array = cfg.get("collapse_same_tick", ["plan", "reflection"])
	if typeof(collapse) != TYPE_ARRAY:
		collapse = ["plan", "reflection"]
	var origin_tick: int = int(cfg.get("origin_cluster_tick", 1))
	var origin_scale: float = float(cfg.get("origin_recency_scale", 0.25))
	var latest_same_tick: Dictionary = _latest_id_by_tick_category(collapse)
	var ranked: Array = []
	for mem in _memories:
		var mem_tick: int = int(mem.get("tick", 0))
		if drop_future and mem_tick > current_tick:
			continue
		if current_tick - mem_tick > time_window:
			continue
		var cat: String = str(mem.get("category", ""))
		var exclude: Array = cfg.get("exclude_categories", [])
		if cat in exclude:
			continue
		if cat in collapse:
			var key: String = _tick_category_key(mem_tick, cat)
			if int(mem.get("id", 0)) != int(latest_same_tick.get(key, -1)):
				continue
		var recency := 1.0
		if time_window > 0:
			recency = clampf(1.0 - float(current_tick - mem_tick) / float(time_window), 0.0, 1.0)
		if cat in collapse and mem_tick <= origin_tick and origin_scale < 1.0:
			recency *= clampf(origin_scale, 0.0, 1.0)
		var sim := _similarity(query, mem as Dictionary)
		var imp := float(mem.get("importance", 0.1))
		var score := w_sim * sim + w_rec * recency + w_imp * imp
		ranked.append({"mem": mem, "score": score})
	ranked.sort_custom(func(a, b): return a["score"] > b["score"])
	var out: Array = []
	for i in mini(k, ranked.size()):
		out.append(ranked[i]["mem"])
	return out


func _latest_id_by_tick_category(categories: Array) -> Dictionary:
	var latest: Dictionary = {}
	for mem in _memories:
		var cat: String = str(mem.get("category", ""))
		if not cat in categories:
			continue
		var key: String = _tick_category_key(int(mem.get("tick", 0)), cat)
		var id: int = int(mem.get("id", 0))
		if id > int(latest.get(key, -1)):
			latest[key] = id
	return latest


func _tick_category_key(tick: int, category: String) -> String:
	return "%d|%s" % [tick, category]


func apply_decay(current_tick: int, cfg: Dictionary) -> void:
	var threshold: float = float(cfg.get("importance_threshold_for_permanent", 0.7))
	var amount: float = float(cfg.get("decay_amount", 0.02))
	var changed := false
	for mem in _memories:
		var imp: float = float(mem.get("importance", 0.0))
		if imp >= threshold:
			continue
		mem["importance"] = maxf(0.01, imp - amount)
		changed = true
	if changed:
		_save()


func latest_reflection_summary() -> String:
	for i in range(_memories.size() - 1, -1, -1):
		var mem: Dictionary = _memories[i]
		if str(mem.get("category", "")) == "reflection":
			return str(mem.get("text", ""))
	return "（尚无反思）"


func _load() -> void:
	_memories.clear()
	_next_id = 1
	if not FileAccess.file_exists(_path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	_memories = parsed.get("memories", [])
	_next_id = int(parsed.get("next_id", _memories.size() + 1))
	var dirty := false
	for mem in _memories:
		if typeof(mem) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = mem
		if _needs_embedding(row):
			_ensure_embedding(row)
			dirty = true
	if dirty:
		_save()


func _save() -> void:
	var file := FileAccess.open(_path, FileAccess.WRITE)
	if file == null:
		push_warning("[MemoryStore] cannot write %s" % _path)
		return
	file.store_string(JSON.stringify({"memories": _memories, "next_id": _next_id}))
	file.close()


func _similarity(query: String, mem: Dictionary) -> float:
	if not _vector_enabled():
		return _text_similarity(query, str(mem.get("text", "")))
	var dim: int = _vector_dim()
	var qv := MemoryEmbed.embed(query, dim)
	return MemoryEmbed.cosine(qv, _memory_vector(mem, dim))


func _memory_vector(mem: Dictionary, dim: int) -> PackedFloat32Array:
	if mem.has("embedding") and typeof(mem["embedding"]) == TYPE_ARRAY:
		var stored: Array = mem["embedding"]
		if stored.size() == dim:
			return MemoryEmbed.from_array(stored, dim)
	_ensure_embedding(mem)
	return MemoryEmbed.from_array(mem.get("embedding", []), dim)


func _needs_embedding(mem: Dictionary) -> bool:
	if not _vector_enabled():
		return false
	var dim: int = _vector_dim()
	return not mem.has("embedding") or typeof(mem["embedding"]) != TYPE_ARRAY or mem["embedding"].size() != dim


func _ensure_embedding(mem: Dictionary) -> void:
	if not _needs_embedding(mem):
		return
	var dim: int = _vector_dim()
	mem["embedding"] = MemoryEmbed.to_array(MemoryEmbed.embed(str(mem.get("text", "")), dim))


func _vector_enabled() -> bool:
	var raw: Variant = Config.memory_retrieval_cfg().get("vector", {})
	if typeof(raw) != TYPE_DICTIONARY:
		return true
	return bool(raw.get("enabled", true))


func _vector_dim() -> int:
	var raw: Variant = Config.memory_retrieval_cfg().get("vector", {})
	if typeof(raw) != TYPE_DICTIONARY:
		return 64
	return maxi(8, int(raw.get("dim", 64)))


func _text_similarity(a: String, b: String) -> float:
	var wa := _words(a)
	var wb := _words(b)
	if wa.is_empty() or wb.is_empty():
		return 0.0
	var inter := 0
	for w in wa:
		if wb.has(w):
			inter += 1
	return float(inter) / float(maxi(wa.size(), wb.size()))


func _words(text: String) -> Dictionary:
	var out: Dictionary = {}
	for part in text.to_lower().split(" ", false):
		var w := part.strip_edges()
		if w.length() >= 2:
			out[w] = true
	return out
