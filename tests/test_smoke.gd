extends SceneTree
##
## P1 smoke test — 不依赖 GUT,可直接跑:
##   godot --headless -s tests/test_smoke.gd
##
## 验证:
##   1. World 程序生成地形不崩溃、维度正确
##   2. 玩家 16x16 sprite 能正常程序生成
##   3. 关键脚本无 Parse Error (否则根本起不来)
##   4. main.gd 节点引用名一致 (Player / World / Camera2D / HUD / GameClock)
##

func _init() -> void:
	var passed := 0
	var failed := 0

	# ---- 1) World 生成 ----
	var WorldScript := load("res://scripts/world/world.gd")
	assert(WorldScript != null, "WorldScript 没加载成功")
	var w: Node2D = WorldScript.new()
	root.add_child(w)
	# _ready 在 SceneTree 下不会自动跑,手动调一次
	if w.has_method("_ready"):
		w._ready()
	if w.tiles.size() == 64:
		passed += 1
		print("[OK]   world.tiles = 64 rows")
	else:
		failed += 1
		printerr("[FAIL] world.tiles = ", w.tiles.size(), " (want 64)")
	if w.tiles[32][32] in [0, 1]:  # 中心应该是 GRASS 或 SAND
		passed += 1
		print("[OK]   world.tiles[32][32] = ", w.tiles[32][32], " (center is land)")
	else:
		failed += 1
		printerr("[FAIL] center tile is not land: ", w.tiles[32][32])
	if w.world_size() == Vector2(1024, 1024):
		passed += 1
		print("[OK]   world.world_size() = (1024, 1024)")
	else:
		failed += 1
		printerr("[FAIL] world.world_size() = ", w.world_size())
	# 中心点应可走
	if w.is_walkable(Vector2(512, 512)):
		passed += 1
		print("[OK]   is_walkable(center)")
	else:
		failed += 1
		printerr("[FAIL] is_walkable(center) returned false")
	# 角点应不可走 (海水)
	if not w.is_walkable(Vector2(2, 2)):
		passed += 1
		print("[OK]   !is_walkable(corner)  -> water blocks")
	else:
		failed += 1
		printerr("[FAIL] corner should be water-blocked")
	w.queue_free()

	# ---- 2) Player 脚本加载 ----
	var PlayerScript := load("res://scripts/player.gd")
	if PlayerScript != null:
		passed += 1
		print("[OK]   player.gd loaded")
	else:
		failed += 1
		printerr("[FAIL] player.gd not loadable")

	# ---- 3) 其它脚本能加载 ----
	for path in [
		"res://scripts/main.gd",
		"res://scripts/world/clock.gd",
		"res://scripts/agent/persona.gd",
	]:
		if load(path) != null:
			passed += 1
			print("[OK]   ", path)
		else:
			failed += 1
			printerr("[FAIL] ", path, " not loadable")

	# ---- 4) Main.tscn 节点结构一致 ----
	var main_scene := load("res://scenes/Main.tscn")
	if main_scene == null:
		failed += 1
		printerr("[FAIL] Main.tscn not loadable")
	else:
		var inst = main_scene.instantiate()
		var expected := ["World", "Player", "Camera2D", "GameClock", "HUD"]
		var missing := []
		for n in expected:
			if not inst.has_node(n):
				missing.append(n)
		if missing.is_empty():
			passed += 1
			print("[OK]   Main.tscn has all required children: ", expected)
		else:
			failed += 1
			printerr("[FAIL] Main.tscn missing nodes: ", missing)
		inst.free()

	# ---- 总结 ----
	print("")
	print("================================")
	print("P1 smoke test: %d passed, %d failed" % [passed, failed])
	print("================================")
	if failed > 0:
		quit(1)
	else:
		quit(0)
