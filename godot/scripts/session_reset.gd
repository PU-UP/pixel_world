class_name SessionReset
##
## 清除运行时持久化数据（记忆、关系）
##


static func wipe_persisted_agent_data() -> void:
	_clear_dir_files(Config.repo_root().path_join("data/memory"))
	_clear_dir_files(Config.repo_root().path_join("data/relationships"))
	_clear_dir_files(Config.repo_root().path_join("data/goals"))


static func _clear_dir_files(dir_path: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir_path)
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".json"):
			DirAccess.remove_absolute(dir_path.path_join(name))
		name = dir.get_next()
	dir.list_dir_end()
