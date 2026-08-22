extends Node
class_name AgentRelationships
##
## 关系网络 — familiarity / affinity / trust, JSON 持久化
##

var agent_id: String = ""
var _edges: Dictionary = {}
var _path: String = ""


func open(for_agent_id: String) -> void:
	agent_id = for_agent_id
	var dir := Config.repo_root().path_join("data/relationships")
	DirAccess.make_dir_recursive_absolute(dir)
	_path = dir.path_join("%s.json" % agent_id)
	_load()


func get_edge(other_id: String) -> Dictionary:
	var key := other_id.strip_edges()
	if key.is_empty() or key == agent_id:
		return _blank_edge()
	if not _edges.has(key):
		_edges[key] = _blank_edge()
	return _edges[key]


func on_spoke_to(other_id: String) -> void:
	var cfg: Dictionary = Config.relationships_cfg().get("on_say_to", {})
	_bump(other_id, cfg)


func on_heard_from(other_id: String) -> void:
	var cfg: Dictionary = Config.relationships_cfg().get("on_heard", {})
	_bump(other_id, cfg)


func on_co_presence(other_id: String) -> void:
	var cfg: Dictionary = Config.relationships_cfg().get("on_co_presence", {})
	_bump(other_id, cfg)


func on_gave_to(other_id: String) -> void:
	var cfg: Dictionary = Config.relationships_cfg().get("on_give", {})
	_bump(other_id, cfg)


func on_received_from(other_id: String) -> void:
	var cfg: Dictionary = Config.relationships_cfg().get("on_received", {})
	_bump(other_id, cfg)


func greet_threshold() -> float:
	return float(Config.relationships_cfg().get("greet_familiarity", 0.35))


func should_greet(other_id: String) -> bool:
	return get_edge(other_id)["familiarity"] >= greet_threshold()


func format_for_hud(all_agent_ids: Array) -> String:
	if _edges.is_empty():
		return "  (no relationships yet)"
	var lines: PackedStringArray = []
	for oid in all_agent_ids:
		var other := str(oid)
		if other == agent_id:
			continue
		var e: Dictionary = get_edge(other)
		if float(e["familiarity"]) < 0.01 and float(e["affinity"]) < 0.01:
			continue
		lines.append(
			"  → %-10s  fam=%.2f  aff=%.2f  trust=%.2f" % [
				other,
				float(e["familiarity"]),
				float(e["affinity"]),
				float(e["trust"]),
			]
		)
	return "\n".join(lines) if lines.size() > 0 else "  (no relationships yet)"


func format_for_decision(nearby_ids: PackedStringArray) -> PackedStringArray:
	var lines: PackedStringArray = []
	for oid in nearby_ids:
		var e: Dictionary = get_edge(str(oid))
		var tag := "stranger"
		if float(e["familiarity"]) >= greet_threshold():
			tag = "familiar"
		lines.append(
			"%s: fam=%.2f aff=%.2f trust=%.2f (%s)" % [
				oid, float(e["familiarity"]), float(e["affinity"]), float(e["trust"]), tag
			]
		)
	return lines


func format_network_ascii(all_agent_ids: Array) -> String:
	var ids: Array = []
	for oid in all_agent_ids:
		var s := str(oid)
		if s != agent_id:
			ids.append(s)
	if ids.is_empty():
		return "(alone)"
	var parts: PackedStringArray = []
	for other in ids:
		var e: Dictionary = get_edge(other)
		if float(e["familiarity"]) >= 0.15:
			parts.append("%s~%.0f%%" % [other.substr(0, 1).to_upper(), float(e["familiarity"]) * 100.0])
	var center := str(agent_id).substr(0, 1).to_upper()
	if parts.is_empty():
		return "%s" % center
	return "%s — %s" % [center, " · ".join(parts)]


func _bump(other_id: String, cfg: Dictionary) -> void:
	var e: Dictionary = get_edge(other_id)
	e["familiarity"] = clampf(float(e["familiarity"]) + float(cfg.get("familiarity", 0.0)), 0.0, 1.0)
	e["affinity"] = clampf(float(e["affinity"]) + float(cfg.get("affinity", 0.0)), 0.0, 1.0)
	e["trust"] = clampf(float(e["trust"]) + float(cfg.get("trust", 0.0)), 0.0, 1.0)
	_edges[other_id] = e
	_save()


func _blank_edge() -> Dictionary:
	return {"familiarity": 0.0, "affinity": 0.0, "trust": 0.0}


func _load() -> void:
	_edges.clear()
	if not FileAccess.file_exists(_path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	_edges = parsed.get("edges", {})


func _save() -> void:
	var file := FileAccess.open(_path, FileAccess.WRITE)
	if file == null:
		push_warning("[AgentRelationships] cannot write %s" % _path)
		return
	file.store_string(JSON.stringify({"agent_id": agent_id, "edges": _edges}))
	file.close()
