extends SceneTree
##
## P1 smoke test — 不依赖 GUT,可直接跑:
##   godot --headless -s tests/test_smoke.gd
##
## 验证:
##   1. World 程序生成地形不崩溃、维度正确
##   2. 玩家 16x16 sprite 能正常程序生成
##   3. 关键脚本无 Parse Error (否则根本起不来)
##   4. main.gd 节点引用名一致 (World / Agents / Camera2D / HUD / GameClock)
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
	var map_h: int = w.MAP_HEIGHT
	var map_w: int = w.MAP_WIDTH
	if w.tiles.size() == map_h:
		passed += 1
		print("[OK]   world.tiles = ", map_h, " rows")
	else:
		failed += 1
		printerr("[FAIL] world.tiles = ", w.tiles.size(), " (want ", map_h, ")")
	var cx: int = int(map_w / 2)
	var cy: int = int(map_h / 2)
	if w.tiles[cy][cx] in [0, 1, 4]:
		passed += 1
		print("[OK]   world.tiles[", cy, "][", cx, "] = ", w.tiles[cy][cx], " (center is land or mountain)")
	else:
		failed += 1
		printerr("[FAIL] center tile is not land or mountain: ", w.tiles[cy][cx])
	var expected_size := Vector2(map_w * 16, map_h * 16)
	if w.world_size() == expected_size:
		passed += 1
		print("[OK]   world.world_size() = ", expected_size)
	else:
		failed += 1
		printerr("[FAIL] world.world_size() = ", w.world_size(), " want ", expected_size)
	var center_px := Vector2(cx * 16 + 8, cy * 16 + 8)
	var center_tile: int = w.tile_at(center_px)
	if w.is_walkable(center_px) or center_tile == 4:
		passed += 1
		print("[OK]   center tile is non-water (tile=", center_tile, ", walkable=", w.is_walkable(center_px), ")")
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
		var expected := ["World", "Agents", "Camera2D", "GameClock", "HUD", "LlmClient", "AgentCoordinator"]
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

		# ---- 4b) HUD 观测面板核心 Label ----
		var hud_base := "HUD/Root/HBox/ObservePanel/ObserveVBox"
		var hud_labels := {
			"StatusLabel": hud_base + "/StatusLabel",
			"AgentLabel": hud_base + "/AgentLabel",
			"ObservationLabel": hud_base + "/ObsScroll/ObservationLabel",
			"ActionLogLabel": hud_base + "/ActionScroll/ActionLogLabel",
			"DecisionLabel": hud_base + "/DecisionScroll/DecisionLabel",
			"RosterLabel": hud_base + "/RosterScroll/RosterLabel",
		}
		var hud_missing := []
		for label_name in hud_labels:
			if not inst.has_node(hud_labels[label_name]):
				hud_missing.append(label_name)
		if hud_missing.is_empty():
			passed += 1
			print("[OK]   HUD observe panel has core labels: ", hud_labels.keys())
		else:
			failed += 1
			printerr("[FAIL] HUD observe panel missing labels: ", hud_missing)
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

	# ---- 7) P2 — actions schema 校验 ----
	var A: Script = load("res://scripts/agent/actions.gd")
	if A != null:
		# 合法 MOVE_TO
		var v1: Dictionary = A.validate({"kind": "MOVE_TO", "params": {"x": 5, "y": 5}})
		if v1["ok"]:
			passed += 1
			print("[OK]   actions.validate: legal MOVE_TO accepted")
		else:
			failed += 1
			printerr("[FAIL] actions.validate legal: ", v1)
		# 缺 x
		var v2: Dictionary = A.validate({"kind": "MOVE_TO", "params": {"y": 5}})
		if not v2["ok"]:
			passed += 1
			print("[OK]   actions.validate: missing x rejected (", v2["error"], ")")
		else:
			failed += 1
			printerr("[FAIL] actions.validate should reject missing x")
		# 未知 kind
		var v3: Dictionary = A.validate({"kind": "FLY", "params": {}})
		if not v3["ok"]:
			passed += 1
			print("[OK]   actions.validate: unknown kind rejected")
		else:
			failed += 1
			printerr("[FAIL] actions.validate should reject unknown kind")
		# 类型错 (x 应该是 int, 传 string)
		var v4: Dictionary = A.validate({"kind": "MOVE_TO", "params": {"x": "5", "y": 5}})
		if not v4["ok"]:
			passed += 1
			print("[OK]   actions.validate: type mismatch rejected")
		else:
			failed += 1
			printerr("[FAIL] actions.validate should reject x:string")
		# make_move_to 工厂
		var f1: Dictionary = A.make_move_to(3, 7)
		if f1["kind"] == "MOVE_TO" and f1["params"]["x"] == 3 and f1["params"]["y"] == 7:
			passed += 1
			print("[OK]   actions.make_move_to(3, 7) factory")
		else:
			failed += 1
			printerr("[FAIL] make_move_to: ", f1)
		# tick_cost: MOVE_TO path_len=5
		var tc1: int = A.tick_cost(A.make_move_to(0, 0), 5)
		if tc1 == 5:
			passed += 1
			print("[OK]   actions.tick_cost MOVE_TO path=5 -> 5 ticks")
		else:
			failed += 1
			printerr("[FAIL] tick_cost MOVE_TO: ", tc1)
		# tick_cost: WAIT 3 ticks
		var tc2: int = A.tick_cost({"kind": "WAIT", "params": {"ticks": 3}})
		if tc2 == 3:
			passed += 1
			print("[OK]   actions.tick_cost WAIT(3) -> 3 ticks")
		else:
			failed += 1
			printerr("[FAIL] tick_cost WAIT: ", tc2)
		# IMPLEMENTED_KINDS 应包含核心原语
		var required_kinds := ["MOVE_TO", "SAY", "PICK_UP", "OBSERVE", "WAIT", "SLEEP"]
		var kinds_ok := true
		for kind in required_kinds:
			if kind not in A.IMPLEMENTED_KINDS:
				kinds_ok = false
				break
		if kinds_ok:
			passed += 1
			print("[OK]   actions.IMPLEMENTED_KINDS includes core primitives: ", required_kinds)
		else:
			failed += 1
			printerr("[FAIL] IMPLEMENTED_KINDS missing core primitive: ", A.IMPLEMENTED_KINDS)

	# ---- 8) P2 — Player 队列接口 ----
	var P2: Script = load("res://scripts/player.gd")
	if P2 != null:
		var p2: Node = P2.new()
		# 初始 IDLE
		if p2._state == 0 and p2._action_queue.is_empty():   # 0 = IDLE
			passed += 1
			print("[OK]   player initial state IDLE, queue empty")
		else:
			failed += 1
			printerr("[FAIL] player init state/queue")
		# 注入合法 MOVE_TO
		p2._world = null  # 还没 bind, 但 validate 不依赖 world
		p2.enqueue_action({"kind": "MOVE_TO", "params": {"x": 10, "y": 10}})
		if p2._action_queue.size() == 1:
			passed += 1
			print("[OK]   player.enqueue_action legal appends 1")
		else:
			failed += 1
			printerr("[FAIL] enqueue_action legal: queue=", p2._action_queue.size())
		# 注入未实现的 EMOTE -> 拒绝 + 写 log
		var log_before: int = p2.action_log.size()
		p2.enqueue_action({"kind": "EMOTE", "params": {"emoji": "?"}})
		if p2._action_queue.size() == 1 and p2.action_log.size() > log_before:
			passed += 1
			print("[OK]   player.enqueue_action unimplemented EMOTE rejected, logged")
		else:
			failed += 1
			printerr("[FAIL] enqueue_action unimplemented: queue=", p2._action_queue.size(), " log=", p2.action_log.size())
		# 注入非法 action (缺 x) -> 拒绝
		var q_before: int = p2._action_queue.size()
		p2.enqueue_action({"kind": "MOVE_TO", "params": {"y": 10}})
		if p2._action_queue.size() == q_before:
			passed += 1
			print("[OK]   player.enqueue_action invalid (missing x) rejected")
		else:
			failed += 1
			printerr("[FAIL] enqueue_action invalid: queue=", p2._action_queue.size())
		# 接口存在
		if p2.has_method("enqueue_move_to_world") and p2.has_method("enqueue_move_to_tile") and p2.has_method("clear_action_queue"):
			passed += 1
			print("[OK]   player has enqueue_move_to_world / _tile / clear_action_queue")
		else:
			failed += 1
			printerr("[FAIL] player missing P2 methods")
		# 状态行应包含 'state='
		var status: String = p2.get_status_line()
		if status.find("state=") >= 0 and status.find("q=") >= 0:
			passed += 1
			print("[OK]   player.get_status_line includes state & queue")
		else:
			failed += 1
			printerr("[FAIL] get_status_line: ", status)
		p2.free()

	# ---- 总结 ----
	print("")
	print("================================")
	print("smoke test: %d passed, %d failed" % [passed, failed])
	print("================================")
	if failed > 0:
		quit(1)
	else:
		quit(0)
