class_name SaveGame
##
## 世界续局 — data/saves/{filename}（默认 world.json）
## 记忆/关系仍走各自 JSON；本文件存 tick、位置、迷雾、物品、地形覆盖、观察者偏好。
##

const VERSION: int = 1


static func slot_path() -> String:
	var name: String = str(Config.save_cfg().get("filename", "world.json"))
	if name.is_empty():
		name = "world.json"
	var dir: String = Config.repo_root().path_join("data/saves")
	return dir.path_join(name)


static func enabled() -> bool:
	return bool(Config.save_cfg().get("enabled", true))


static func autosave_ticks() -> int:
	return int(Config.save_cfg().get("autosave_ticks", 25))


static func write(payload: Dictionary) -> bool:
	if not enabled():
		return false
	var path: String = slot_path()
	var dir: String = path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("[SaveGame] cannot write %s" % path)
		return false
	var data: Dictionary = payload.duplicate(true)
	data["version"] = VERSION
	file.store_string(JSON.stringify(data))
	file.close()
	return true


static func read() -> Dictionary:
	if not enabled():
		return {}
	var path: String = slot_path()
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("[SaveGame] invalid save %s" % path)
		return {}
	return parsed


static func wipe() -> void:
	var path: String = slot_path()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
