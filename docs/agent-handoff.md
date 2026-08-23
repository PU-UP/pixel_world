# Agent 交接文档 — Pixel World

> 给其他 AI/人类协作者：**当前版本摘要 + 仓库状态 + 下一阶段方向**。  
> 宪法级架构见根目录 [`AGENTS.md`](./../AGENTS.md)。

---

## 1. 当前版本快照（v2.0）

| 项 | 说明 |
|---|---|
| **引擎** | Godot 4.7.x，`godot/project.godot` |
| **地图** | 96×96 瓦片，程序化色块（非 TileMap 美术） |
| **Agent** | 5 个 LLM agent，MiniMax function calling |
| **观测** | HUD + `data/logs/` + `tools/digest_session.py`（**无局内回放 UI**） |
| **Git** | `main` 含 v1.1（P8 日志/门控）+ v2.0（迷雾/目标/共享地图） |

### v2.0 已交付

- 战争迷雾三层：**亮**（当前感知半径）、**灰**（已探索）、**黑**（未探索）
- **G** 切换上帝视角：全岛缩放、地形无迷雾
- 每 agent **长期目标 + 当前目标**（`agents.yaml` + `data/goals/` + prompt）
- 行动原语 **`SHARE_MAP`**：双方互发后合并灰色已探索格
- P8.4：OBSERVE 超距靠近、重复 MOVE 跳过、SAY 长度上限

### v1.1 已交付（摘要）

- 决策 gate、`resolve_move_goal`、动态 tool enum、日志 digest、token 节流

---

## 2. 代码地图（高频改动点）

```
config/           world.yaml agents.yaml runtime.yaml llm.yaml
godot/scripts/
  main.gd         入口、HUD、G 上帝视角、迷雾绑定
  player.gd       移动、感知、exploration 更新、行动执行
  agent/
    decision.gd   LLM 决策 + gate + redirect
    actions.gd    原语 schema / validate_in_context
    comm.gd       SAY/GIVE/SHARE_MAP 路由
    goals.gd      目标持久化
    coordinator.gd  agent 生命周期
  world/
    world.gd      地图生成与绘制
    exploration_map.gd  每 agent 探索位图（仅「是否见过」）
  ui/
    fog_of_war.gd 地形迷雾遮罩
    minimap.gd    小地图迷雾
    camera_rig.gd 跟随 / 上帝缩放
tools/
  digest_session.py summarize_session.py reset_game.py
data/             运行时，不进 git
```

---

## 3. 产品方已识别问题 → 下一阶段优先级

### P2.1 — 真正的「观察者上帝视角」（高）

**现状**：按 **G** 仅关闭 **地形迷雾**；所有 agent **精灵始终在 Agents 层绘制**，在灰色/黑色区域仍可能看到同伴走动。

**目标**：

- 观察者默认或可选模式：**全图地形 + 全 agent 位置 + 全物品** 一览（真正上帝视角 HUD）
- 与「跟随某 agent」模式严格分离：跟随 = 该 agent 的信息边界，上帝 = 无信息边界

**实现提示**：

- `main.gd`：观察者模式枚举 `OBSERVER_GOD | OBSERVER_AGENT | MANUAL`
- 上帝模式下：迷雾关闭 + 小地图全亮 + 可选侧边栏列出所有 agent 坐标/区域/目标
- 考虑默认进入 **OBSERVER_GOD**（产品诉求：缺乏上帝视角）

### P2.2 — 灰色 = 过去记忆，不可见同伴（高）

**现状**：`ExplorationMap` 只存 `explored` 布尔；灰区只遮 **地形**，**不遮 agent**。

**目标**（与 Generative Agents / 公平感知一致）：

- 跟随 agent A 时：**仅 VISIBLE 格**内可看到其他 agent、地面物品、动态事件
- **EXPLORED（灰）**：只显示 **探索时的地形快照**（静态），**不显示** 当前在该格的 agent（他们可能已离开）
- **UNEXPLORED（黑）**：无信息

**实现提示**：

- `exploration_map.gd` 扩展：`explored_tiles["x,y"] -> { terrain: Tile, tick }`
- 渲染：灰区用快照色绘制（或 world 上叠灰 + 用快照色块替代 live tile）
- `player.gd` / `Agents` 层：`visible` 由选中 agent 的 `get_state(tile)==VISIBLE` 决定，灰/黑不绘制其他 agent
- LLM 感知（`get_observation_for_llm`）已与视野一致，需与 **渲染** 对齐

### P2.3 — 探索记忆过时与再探索（中）

**背景**：未来可能有 **地图改动**（物品、建筑、地形事件）。

**目标**：

- 灰色区域 = **历史记忆**；若 live 世界与该格快照不一致，需 agent **再次进入 VISIBLE** 才刷新
- 可选：记忆流写入 `exploration_stale` 事件

**实现提示**：

- 进入 VISIBLE 时对比 `snapshot.terrain` vs `world.tile_at_tile`
- 不一致则更新快照并 append 记忆

### P2.4 — SHARE_MAP 与社交（中）

- digest 统计 `SHARE_MAP` / `map_share_merged`
- prompt 鼓励在信任/协作场景交换地图
- 共享的是 **探索快照** 而非 live 状态（与 P2.2 一致）

### P2.5 — 质量与成本（持续）

- 跑 100+ tick 对比 anomalies、tokens/tick（参考 P8.3 session `12-50-06`）
- sage 长独白：可调 `max_say_chars` 或相似度门控

### P2.6 — 多 agent 扎堆「卡死」互相挡路（高）⚠️ 已观测

**现象（产品方反馈）**：约 3 个 agent 聚在同一区域（常见于社交 `SAY` / `move_closer` / `approach_agent` 后），彼此 **无法通过**，长时间堆在一起，整体几乎不再移动。

**根因分析（代码级，无需游戏录像）**：

| 层 | 现状 | 后果 |
|---|---|---|
| **A\*** `pathfinding.gd` | 只判断 `world.is_walkable_tile`（草地/沙滩） | **不把其他 agent 当作障碍**；多人可同时规划到相邻格或同一会合点 |
| **移动** `player.gd` | `CharacterBody2D` + 14×14 `CollisionShape2D` + `move_and_slide()` | agent **物理碰撞**；挤在一起时推不动，但状态仍为 `WALKING` |
| **路径推进** `_advance_along_path` | 仅当 `dist < 1.0` 才 `path_idx++` | 被挡住时 **永远到不了 waypoint**，路径 **永不结束** |
| **决策** `decision.gd` | `skip_while_walking: true` → `is_busy()` 时 **不调 LLM** | 卡住的 agent **无法重新决策**（不能 WAIT / 换目标 / 绕路） |
| **社交** gate | `move_closer` / `approach_agent` 常 `MOVE_TO` **对方脚下格** | explorer/sage/guardian 等趋向 **同一坐标**，加剧拥堵 |
| **日志** `logger.gd` `_track_stuck_agents` | 只统计 snapshot 时 **idle 同格** | **WALKING 顶墙** 不会被记为 stuck |

**典型复现场景**：中央草甸 `(48,48)` 附近 — sage 广播邀约 → explorer/guardian `MOVE_TO` 靠近 sage → 三人占 3 邻格或争同一格 → 第四人（scout/wanderer）再靠近 → 物理碰撞链式阻塞。

**日志中如何验证**（给无录像的 agent）：

```powershell
python tools/summarize_session.py
# 关注：某 agent 长时间 walking + queue_len>0 + 坐标抖动或不变
# digest：同一 tick 段内多 agent 坐标曼哈顿距离 ≤2 且 action 多为 MOVE_TO
# jsonl：action_result MOVE_TO ok + path_len>0，但后续 snapshot state 长期 walking
```

**解决方案（建议分阶段，需写入 `AGENTS.md` 移动语义后实现）**：

| 方案 | 做法 | 优点 | 缺点 |
|---|---|---|---|
| **A. 移动超时解锁**（推荐 **先做**） | `player.gd`：WALKING 时若 N tick 内 `global_position` 位移 &lt; ε，abort 路径 → `IDLE`，记 `movement_stuck` anomaly，允许重新决策 | 改动小，立刻解除「永久 busy」 | 不解决拥堵，只避免死锁 |
| **B. 寻路占格** | `world/state.gd` 维护 `agent_tile` 占用；A\* 跳过被占格（或仅跳过非目标占格） | 符合「一格一人」直觉 | 需协调占格释放、目标格例外 |
| **C. agent 间不碰撞** | Godot `collision_layer`：agent 不与 agent 层碰撞，只与地形（若有） | 实现快，GBA 常见 | 精灵可重叠，观感略假 |
| **D. 会合语义** | `move_closer` / `approach_agent` 不指向 `other.tile`，而是 **邻格环** 上最近可走且未占用的格 | 减少社交扎堆抢中心格 | 需 `resolve_adjacent_meeting_tile()` |
| **E. 社交原地** | 已在 `audio` 内则 **不 redirect MOVE**，直接 SAY | 减少无意义靠近 | 需区分「看得见但听不见」 |

**推荐实施顺序**：

```
P2.6a 移动超时 + movement_stuck 日志（1 天）
  → P2.6b move_closer 改为邻格会合点（1 天）
  → P2.6c A* 占格 或 agent 软碰撞（2 天，二选一，在 AGENTS.md 定稿）
```

**验收标准**：

- 三人围聊 50 tick 后仍能各自离开或继续行动（无永久 `walking`）
- `data/logs` 出现 `movement_stuck` 时 agent 能在下一决策 tick 恢复
- digest 中同区域 agent 不再出现 **全员 walking + 坐标不变 &gt;30 tick**

---

## 4. 建议迭代顺序

```
P2.1 观察者上帝模式（默认全可视 HUD）
  → P2.2 agent 精灵/物品按 VISIBLE 裁剪 + 灰区地形快照
  → P2.6a 移动卡死解锁（与 P2.2 可并行，建议尽早）
  → P2.6b/c 会合语义 + 占格/碰撞策略
  → P2.3 再探索刷新快照
  → P2.4 SHARE_MAP 与快照模型对齐
  → P2.5 日志回归 + prompt 微调
```

预估：**P2.1 + P2.2** 约 3–5 天；**P2.6a** 约 1 天（建议插队）。

---

## 5. 验收与运维命令

```powershell
# 清运行时（含 goals）
python tools/reset_game.py
python tools/reset_game.py --logs

# 局后分析
python tools/summarize_session.py
python tools/digest_session.py data/logs/<session>.jsonl

# 验收清单
docs/v2.0-acceptance.md
```

---

## 6. 不要做的事

- 不要加 **局内时间轴回放 UI**（用 `data/logs/` + digest 给外部 agent 复盘）
- 不要把 `data/`、`.env` 提交 git
- 大幅改架构前先更新 `AGENTS.md`

---

_最后更新：v2.0 验收 + P2.6 多 agent 卡死分析（产品方观测）。_
