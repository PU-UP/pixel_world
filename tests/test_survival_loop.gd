extends SceneTree
##
## v2.10 细节修复 — 不依赖 GUT:
##   godot --path godot --headless -s res://../tests/test_survival_loop.gd
##

func _init() -> void:
	var passed := 0
	var failed := 0

	var vitals: AgentVitals = AgentVitals.new()
	vitals.reset()
	vitals.health = 80.0
	vitals.night_sleep_ticks = 100
	vitals.ate_this_day = false
	vitals.last_day_index = 0
	vitals.on_tick(1, "dawn", false, false)
	# 睡够但没吃：只扣断食，不再叠 recover_one
	if is_equal_approx(vitals.health, 74.0) and vitals.days_without_food == 1 and vitals.nights_without_sleep == 0:
		passed += 1
		print("[OK]   health dawn: slept/no-food deducts miss_food only (80-6=74)")
	else:
		failed += 1
		printerr("[FAIL] health dawn slept/no-food: health=", vitals.health, " days=", vitals.days_without_food)

	vitals.reset()
	vitals.health = 80.0
	vitals.night_sleep_ticks = 0
	vitals.ate_this_day = true
	vitals.last_day_index = 0
	vitals.on_tick(1, "dawn", false, false)
	if is_equal_approx(vitals.health, 75.0) and vitals.nights_without_sleep == 1:
		passed += 1
		print("[OK]   health dawn: ate/no-sleep deducts miss_sleep only (80-5=75)")
	else:
		failed += 1
		printerr("[FAIL] health dawn ate/no-sleep: health=", vitals.health, " nights=", vitals.nights_without_sleep)

	vitals.reset()
	vitals.health = 80.0
	vitals.night_sleep_ticks = 100
	vitals.ate_this_day = true
	vitals.last_day_index = 0
	vitals.on_tick(1, "dawn", false, false)
	if is_equal_approx(vitals.health, 87.0):
		passed += 1
		print("[OK]   health dawn: slept+ate recovers both (80+7=87)")
	else:
		failed += 1
		printerr("[FAIL] health dawn both done: health=", vitals.health)

	vitals.reset()
	vitals.health = 0.0
	if vitals.is_deceased():
		passed += 1
		print("[OK]   health 0 is deceased")
	else:
		failed += 1
		printerr("[FAIL] health 0 should be deceased")

	var A: Script = load("res://scripts/agent/actions.gd")
	var say_fail: Dictionary = A.validate_in_context(
		{"kind": "SAY", "params": {"to": "broadcast", "text": "有人吗"}},
		{"sight_agent_ids": [], "all_agent_ids": ["scout"]},
	)
	if not say_fail["ok"] and str(say_fail.get("error", "")).find("sight") >= 0:
		passed += 1
		print("[OK]   SAY broadcast with empty sight rejected")
	else:
		failed += 1
		printerr("[FAIL] SAY broadcast empty sight: ", say_fail)

	var say_ok: Dictionary = A.validate_in_context(
		{"kind": "SAY", "params": {"to": "broadcast", "text": "有人吗"}},
		{"sight_agent_ids": ["scout"], "all_agent_ids": ["scout"]},
	)
	if say_ok["ok"]:
		passed += 1
		print("[OK]   SAY broadcast with living sight accepted")
	else:
		failed += 1
		printerr("[FAIL] SAY broadcast with sight: ", say_ok)

	var use_fail: Dictionary = A.validate_in_context(
		{"kind": "USE", "params": {"item": "flint", "on": "self"}},
		{"inventory": ["flint"]},
	)
	if not use_fail["ok"] and str(use_fail.get("error", "")).find("改变地形") >= 0:
		passed += 1
		print("[OK]   USE flint rejected with island-cannot-craft reason")
	else:
		failed += 1
		printerr("[FAIL] USE flint: ", use_fail)

	var use_food: Dictionary = A.validate_in_context(
		{"kind": "USE", "params": {"item": "berry_bush", "on": "self"}},
		{"inventory": ["berry_bush"]},
	)
	if use_food["ok"]:
		passed += 1
		print("[OK]   USE berry_bush on self accepted")
	else:
		failed += 1
		printerr("[FAIL] USE berry_bush: ", use_food)

	if A.normalize_pickup_item("野果") == A.PICK_UP_ALL_FOOD and Config.is_food_gather_token("全部"):
		passed += 1
		print("[OK]   all_food tokens include 野果/全部")
	else:
		failed += 1
		printerr("[FAIL] food gather token normalize")

	var msgs: Array = DecisionPrompt.build_messages(
		"persona",
		"obs",
		"status",
		PackedStringArray(),
		PackedStringArray(["scout", "sage"]),
		PackedStringArray(["scout"]),
	)
	var user: String = str(msgs[1]["content"])
	if user.find("=== Visible corpses ===") >= 0 and user.find("sage") >= 0 and user.find("scout") >= 0:
		passed += 1
		print("[OK]   prompt lists corpses even when living agents are also in sight")
	else:
		failed += 1
		printerr("[FAIL] mixed corpse prompt:\n", user)

	var tools: Array = DecisionPrompt.tool_definitions_for_context(
		PackedStringArray(),
		PackedStringArray(),
		PackedStringArray(),
		PackedStringArray(),
		["flint", "rope"],
	)
	var has_use := false
	var has_drop := false
	for tool in tools:
		var name_s: String = str(tool.get("function", {}).get("name", ""))
		if name_s == "USE":
			has_use = true
		if name_s == "DROP":
			has_drop = true
	if has_drop and not has_use:
		passed += 1
		print("[OK]   USE tool omitted when inventory is only flavor items")
	else:
		failed += 1
		printerr("[FAIL] flavor inventory tools use=", has_use, " drop=", has_drop)

	var plan: AgentPlanning = AgentPlanning.new()
	plan._steps = ["MOVE_TO 前往南滩 (48,75)", "SAY 向 scout 打招呼"]
	plan._step_index = 0
	var match_move: bool = plan.step_matches({"kind": "MOVE_TO", "params": {"x": 48, "y": 75}})
	var skip_wait: bool = not plan.step_matches({"kind": "WAIT", "params": {"ticks": 2}})
	var skip_wrong: bool = not plan.step_matches({"kind": "MOVE_TO", "params": {"x": 10, "y": 10}})
	plan.advance_if_matches({"kind": "MOVE_TO", "params": {"x": 48, "y": 75}})
	var advanced: bool = plan._step_index == 1
	if match_move and skip_wait and skip_wrong and advanced:
		passed += 1
		print("[OK]   plan advances only on matching MOVE_TO coords")
	else:
		failed += 1
		printerr("[FAIL] plan match move=", match_move, " wait=", skip_wait, " wrong=", skip_wrong, " idx=", plan._step_index)
	plan.free()

	var store: MemoryStore = MemoryStore.new()
	store.open("_test_survival_loop")
	store.wipe()
	store.open("_test_survival_loop")
	store.append({"tick": 10, "category": "action", "text": "ok [WAIT] {ticks:2}", "importance": 0.3, "social_relevance": 0.0})
	store.append({"tick": 20, "category": "reflection", "text": "我意识到要先活下去。", "importance": 0.75, "social_relevance": 0.0})
	store.append({"tick": 30, "category": "action", "text": "ok [SAY] {to:scout}", "importance": 0.4, "social_relevance": 0.7})
	var retrieved: Array = store.retrieve("scout 说话", 3, 40, {
		"time_window_ticks": 600,
		"similarity_weight": 0.7,
		"recency_weight": 0.3,
		"importance_weight": 0.2,
		"always_include_reflections": 2,
		"social_boost": 0.25,
		"exclude_categories": ["observation", "decision"],
		"vector": {"enabled": false, "dim": 64},
	})
	var has_reflection := false
	var first_cat := ""
	if retrieved.size() > 0:
		first_cat = str(retrieved[0].get("category", ""))
	for mem in retrieved:
		if str(mem.get("category", "")) == "reflection":
			has_reflection = true
	if has_reflection and first_cat == "reflection":
		passed += 1
		print("[OK]   memory retrieve pins latest reflection first")
	else:
		failed += 1
		printerr("[FAIL] memory pin reflection first_cat=", first_cat, " n=", retrieved.size())
	store.wipe()

	if (
		A.interrupts_walk("USE")
		and A.interrupts_walk("PICK_UP")
		and A.interrupts_walk("SLEEP")
		and not A.interrupts_walk("MOVE_TO")
		and not A.interrupts_walk("WAIT")
		and not A.interrupts_walk("EMOTE")
	):
		passed += 1
		print("[OK]   MOVE_TO/WAIT/EMOTE do not interrupt a walk; USE/PICK_UP/SLEEP do")
	else:
		failed += 1
		printerr("[FAIL] interrupts_walk kinds")

	var pvit: Node = load("res://scripts/player.gd").new()
	pvit.vitals.reset()
	pvit.vitals.energy = 5.0
	pvit.vitals.satiety = 5.0
	var empty_pack: bool = not pvit.can_relieve_vitals_in_place()
	pvit.inventory.append("berry_bush")
	var with_food: bool = pvit.can_relieve_vitals_in_place()
	if empty_pack and with_food:
		passed += 1
		print("[OK]   hungry agent can only relieve vitals in place when carrying food")
	else:
		failed += 1
		printerr("[FAIL] can_relieve empty=", empty_pack, " food=", with_food)
	pvit.free()

	print("")
	print("================================")
	print("survival loop test: %d passed, %d failed" % [passed, failed])
	print("================================")
	if failed > 0:
		quit(1)
	else:
		quit(0)
