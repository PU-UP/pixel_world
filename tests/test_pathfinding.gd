extends SceneTree
##
## P2 A* 单测 — 不依赖 GUT, 可直接跑:
##   godot --headless -s tests/test_pathfinding.gd
##
## 准备一个空 world, 自己造地形, 跑以下场景:
##   1. 起点 = 终点 -> [start]
##   2. 起点不可走 -> 自动找最近可走
##   3. 直路 -> 路径最短
##   4. 不可达 -> []
##   5. 绕路 -> 绕过障碍
##

const AStarPathfinder = preload("res://scripts/world/pathfinding.gd")

func _init() -> void:
	var passed: int = 0
	var failed: int = 0

	# ---- 准备一个简单 16x16 全草地 world ----
	var W: Script = load("res://scripts/world/world.gd")
	var world: Node2D = W.new()
	root.add_child(world)
	# 直接构造 tiles (全 grass)
	world.tiles = []
	for y in 16:
		var row: Array = []
		for x in 16:
			row.append(0)  # GRASS
		world.tiles.append(row)
	# 假装 _ready 已跑过, 后面不会再重置
	world.MAP_WIDTH = 16
	world.MAP_HEIGHT = 16

	# ---- 1) start == goal ----
	var p1: Array = AStarPathfinder.find_path(world, Vector2i(5, 5), Vector2i(5, 5))
	if p1.size() == 1 and p1[0] == Vector2i(5, 5):
		passed += 1
		print("[OK]   test1: start==goal -> [start]")
	else:
		failed += 1
		printerr("[FAIL] test1: ", p1)

	# ---- 2) 直路 ----
	var p2: Array = AStarPathfinder.find_path(world, Vector2i(0, 0), Vector2i(5, 0))
	if p2.size() == 6 and p2[0] == Vector2i(0, 0) and p2[-1] == Vector2i(5, 0):
		passed += 1
		print("[OK]   test2: straight line, length=", p2.size())
	else:
		failed += 1
		printerr("[FAIL] test2: ", p2)

	# ---- 3) 不可达 (goal 在水里) ----
	world.tiles[10][10] = 2  # water
	# 周围 4 邻居也设水, 制造孤立岛
	world.tiles[10][9] = 2
	world.tiles[10][11] = 2
	world.tiles[9][10] = 2
	world.tiles[11][10] = 2
	var p3: Array = AStarPathfinder.find_path(world, Vector2i(0, 0), Vector2i(10, 10))
	if p3.is_empty():
		passed += 1
		print("[OK]   test3: unreachable (water) -> []")
	else:
		failed += 1
		printerr("[FAIL] test3: expected empty, got ", p3)
	# 复原
	for v in [Vector2i(10, 10), Vector2i(10, 9), Vector2i(10, 11), Vector2i(9, 10), Vector2i(11, 10)]:
		world.tiles[int(v.y)][int(v.x)] = 0

	# ---- 4) 绕路: 水平中央放一堵树墙, 必须绕上下 ----
	# 画一条从 (0, 5) 到 (15, 5) 的直路, 中间有树
	for x in range(3, 13):
		world.tiles[5][x] = 3  # tree
	# 留两个缺口: (3,4), (3,6) -> 上面; (12,4), (12,6) -> 下面
	world.tiles[5][3] = 0
	world.tiles[5][12] = 0
	# 改 (3,4) (3,5) (3,6) 都可走, (12,4)(12,5)(12,6) 都可走
	var p4: Array = AStarPathfinder.find_path(world, Vector2i(0, 5), Vector2i(15, 5))
	if not p4.is_empty() and p4[-1] == Vector2i(15, 5):
		# 检查路径不穿过树
		var hits_tree: int = 0
		for t in p4:
			if world.tiles[int(t.y)][int(t.x)] == 3:
				hits_tree += 1
		if hits_tree == 0:
			passed += 1
			print("[OK]   test4: detour around tree wall, length=", p4.size())
		else:
			failed += 1
			printerr("[FAIL] test4: path hit tree ", hits_tree, " times: ", p4)
	else:
		failed += 1
		printerr("[FAIL] test4: no path found: ", p4)
	# 复原
	for x in range(3, 13):
		world.tiles[5][x] = 0

	# ---- 5) 起点不可走, 自动找最近可走 ----
	world.tiles[0][0] = 2  # water at start
	var p5: Array = AStarPathfinder.find_path(world, Vector2i(0, 0), Vector2i(5, 0))
	# 起点会被替换为 (1,0) 或 (0,1)
	if not p5.is_empty() and p5[0] in [Vector2i(1, 0), Vector2i(0, 1)]:
		passed += 1
		print("[OK]   test5: unreachable start auto-snapped to neighbor, starts at ", p5[0])
	else:
		failed += 1
		printerr("[FAIL] test5: ", p5)
	world.tiles[0][0] = 0  # 复原

	# ---- 6) 性能 smoke: 64x64 全空地图, 起点到对角 ----
	var big_w: Node2D = W.new()
	big_w.tiles = []
	for y in 64:
		var row: Array = []
		for x in 64:
			row.append(0)
		big_w.tiles.append(row)
	big_w.MAP_WIDTH = 64
	big_w.MAP_HEIGHT = 64
	var t0: int = Time.get_ticks_msec()
	var p6: Array = AStarPathfinder.find_path(big_w, Vector2i(0, 0), Vector2i(63, 63))
	var t1: int = Time.get_ticks_msec()
	var dt: int = t1 - t0
	if p6.size() == 128 and dt < 500:
		passed += 1
		print("[OK]   test6: 64x64 diag path, length=", p6.size(), " time=", dt, "ms")
	else:
		failed += 1
		printerr("[FAIL] test6: len=", p6.size(), " time=", dt, "ms")
	big_w.free()

	# ---- 7) 不可达的山 ----
	# 把整个岛全设山, 只能从起点走 1 步
	for y in 16:
		for x in 16:
			world.tiles[y][x] = 4  # MOUNTAIN
	# 起点和邻居恢复为 grass
	world.tiles[0][0] = 0
	world.tiles[0][1] = 0
	world.tiles[1][0] = 0
	var p7: Array = AStarPathfinder.find_path(world, Vector2i(0, 0), Vector2i(15, 15))
	if p7.is_empty() or p7.size() < 4:
		# 应该不可达, 最多 2 步
		passed += 1
		print("[OK]   test7: all-mountain, limited path, length=", p7.size())
	else:
		failed += 1
		printerr("[FAIL] test7: unexpected path through mountains: ", p7)

	world.get_parent().remove_child(world)
	world.free()

	# ---- 总结 ----
	print("")
	print("================================")
	print("P2 pathfinding test: %d passed, %d failed" % [passed, failed])
	print("================================")
	if failed > 0:
		quit(1)
	else:
		quit(0)
