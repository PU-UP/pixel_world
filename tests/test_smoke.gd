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
	if w.tiles[32][32] in [0, 1, 4]:  # GRASS / SAND / MOUNTAIN(中心有 35% 概率撞山)
		passed += 1
		print("[OK]   world.tiles[32][32] = ", w.tiles[32][32], " (center is land or mountain)")
	else:
		failed += 1
		printerr("[FAIL] center tile is not land or mountain: ", w.tiles[32][32])
	if w.world_size() == Vector2(1024, 1024):
		passed += 1
		print("[OK]   world.world_size() = (1024, 1024)")
	else:
		failed += 1
		printerr("[FAIL] world.world_size() = ", w.world_size())
	# 中心点是否可走取决于 seed;seed=1337 会撞山 → 不可走
	# 改成:中心点可走 OR 是山(都算地形合法)
	var center_tile: int = w.tile_at(Vector2(512, 512))
	if w.is_walkable(Vector2(512, 512)) or center_tile == 4:
		passed += 1
		print("[OK]   center tile is non-water (tile=", center_tile, ", walkable=", w.is_walkable(Vector2(512, 512)), ")")
	else:
		failed += 1
		printerr("[FAIL] center tile should be land or mountain, got: ", center_tile)
	# 角点应不可走 (海水)
	if not w.is_walkable(Vector2(2, 2)):
		passed += 1
		print("[OK]   !is_walkable(corner)  -> water blocks")
	else:
		failed += 1
		printerr("[FAIL] corner should be water-blocked")
	# SceneTree._init() 阶段 main loop 未跑, queue_free 不保证释放; 用 free + remove_child 更稳
	w.get_parent().remove_child(w)
	w.free()

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

		# ---- 4b) P1.5 HUD 结构:VBox + 4 个 Label ----
		var hud_labels := ["StatusLabel", "AgentLabel", "ObservationLabel", "ActionLogLabel"]
		var hud_missing := []
		for n in hud_labels:
			if not inst.has_node("HUD/VBox/" + n):
				hud_missing.append(n)
		if hud_missing.is_empty():
			passed += 1
			print("[OK]   HUD/VBox has all 4 labels: ", hud_labels)
		else:
			failed += 1
			printerr("[FAIL] HUD/VBox missing labels: ", hud_missing)
		inst.free()

	# ---- 5) P1.5 Player 可观测接口 ----
	var P: Script = load("res://scripts/player.gd")
	if P != null:
		var p: Node = P.new()
		# action_log 存在且初始为空
		if "action_log" in p and p.action_log.size() == 0:
			passed += 1
			print("[OK]   player.action_log exists and is empty")
		else:
			failed += 1
			printerr("[FAIL] player.action_log missing or non-empty")
		# 接口存在
		var has_obs: bool = p.has_method("get_observation")
		var has_status: bool = p.has_method("get_status_line")
		var has_log: bool = p.has_method("get_action_log_lines")
		if has_obs and has_status and has_log:
			passed += 1
			print("[OK]   player has get_observation / get_status_line / get_action_log_lines")
		else:
			failed += 1
			printerr("[FAIL] player missing P1.5 methods: obs=", has_obs, " status=", has_status, " log=", has_log)
		# _log_action 后 action_log 有记录
		p._log_action(1, "test", "hello")
		if p.action_log.size() == 1 and p.action_log[0].text == "hello":
			passed += 1
			print("[OK]   player._log_action appends correctly")
		else:
			failed += 1
			printerr("[FAIL] player._log_action not appending")
		p.free()

	# ---- 6) P1.5 GameClock pause / step ----
	var C: Script = load("res://scripts/world/clock.gd")
	if C != null:
		var c: Node = C.new()
		root.add_child(c)
		c._ready() if c.has_method("_ready") else null
		# paused 初始 false
		if not c.paused:
			passed += 1
			print("[OK]   GameClock.paused starts false")
		else:
			failed += 1
			printerr("[FAIL] GameClock.paused should start false")
		# 暂停后推进一帧,tick 不增
		c.paused = true
		var tick_before: int = c.current_tick()
		c._process(1.0)  # 1 秒 delta
		if c.current_tick() == tick_before:
			passed += 1
			print("[OK]   GameClock.paused=true freezes tick (still ", tick_before, ")")
		else:
			failed += 1
			printerr("[FAIL] GameClock advanced while paused: ", tick_before, " -> ", c.current_tick())
		# tick_once() 即使 paused 也推一 tick
		c.tick_once()
		if c.current_tick() == tick_before + 1:
			passed += 1
			print("[OK]   GameClock.tick_once() forces one tick (now ", c.current_tick(), ")")
		else:
			failed += 1
			printerr("[FAIL] GameClock.tick_once() didn't advance: expected ", tick_before + 1, " got ", c.current_tick())
		c.get_parent().remove_child(c)
		c.free()

	# ---- 总结 ----
	print("")
	print("================================")
	print("P1 + P1.5 smoke test: %d passed, %d failed" % [passed, failed])
	print("================================")
	if failed > 0:
		quit(1)
	else:
		quit(0)
