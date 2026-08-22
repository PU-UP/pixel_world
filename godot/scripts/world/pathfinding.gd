class_name AStarPathfinder
##
## A* 寻路 (4 方向, 瓦片级)
##
## 输入: world 引用 + 起点/终点瓦片坐标 (Vector2i)
## 输出: Array[Vector2i] 路径点 (含起点与终点), 不可达返回空数组
##
## 性能: 64x64 = 4096 节点, 线性扫描 open set 最坏 O(N²) ≈ 16M ops ≈ 100ms
##      地图小,够用; 后期若扩到 256x256 再上 heap
##

const INF: int = 1_000_000
const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
]

# ------------------------------------------------------------------
# 公开接口
# ------------------------------------------------------------------
static func find_path(world, start: Vector2i, goal: Vector2i) -> Array:
	if start == goal:
		return [start]
	# 起点也要求可走(否则玩家卡在墙里)— 但允许起点刚好不可走(等下一 tick 修)
	if not world.is_walkable_tile(goal):
		return []
	if not world.is_walkable_tile(start):
		# 起点不可走, 找最近可走的邻居作为新起点
		var nearest: Vector2i = _nearest_walkable(world, start)
		if nearest == Vector2i.MIN:
			return []
		start = nearest

	var h_start: int = _heuristic(start, goal)
	# open: Array[Dictionary] {pos, f, g}
	var open: Array = [{"pos": start, "f": h_start, "g": 0}]
	var came_from: Dictionary = {}
	var g_score: Dictionary = {start: 0}
	var closed: Dictionary = {}

	while not open.is_empty():
		# 找最小 f_score (O(N) 扫描, N <= 4096 可接受)
		var best_idx: int = 0
		for i in range(1, open.size()):
			if int(open[i]["f"]) < int(open[best_idx]["f"]):
				best_idx = i
		var current: Vector2i = open[best_idx]["pos"]
		open.remove_at(best_idx)

		if current == goal:
			return _reconstruct(came_from, current)

		closed[current] = true

		for d in DIRS:
			var n: Vector2i = current + d
			if closed.has(n):
				continue
			if not world.is_walkable_tile(n):
				continue
			var tentative_g: int = int(g_score[current]) + 1
			if tentative_g < int(g_score.get(n, INF)):
				came_from[n] = current
				g_score[n] = tentative_g
				open.append({
					"pos": n,
					"f": tentative_g + _heuristic(n, goal),
					"g": tentative_g,
				})

	# 不可达
	return []

# ------------------------------------------------------------------
# 内部工具
# ------------------------------------------------------------------
static func _heuristic(a: Vector2i, b: Vector2i) -> int:
	# 曼哈顿距离 (4 方向一致, admissible)
	return abs(a.x - b.x) + abs(a.y - b.y)

static func _reconstruct(came_from: Dictionary, current: Vector2i) -> Array:
	var path: Array = [current]
	while came_from.has(current):
		current = came_from[current]
		path.append(current)
	path.reverse()
	return path

static func _nearest_walkable(world, start: Vector2i) -> Vector2i:
	# 4 方向最近邻居
	for d in DIRS:
		var n: Vector2i = start + d
		if world.is_walkable_tile(n):
			return n
	return Vector2i.MIN
