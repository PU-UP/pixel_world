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

---

## 4. 建议迭代顺序

```
P2.1 观察者上帝模式（默认全可视 HUD）
  → P2.2 agent 精灵/物品按 VISIBLE 裁剪 + 灰区地形快照
  → P2.3 再探索刷新快照
  → P2.4 SHARE_MAP 与快照模型对齐
  → P2.5 日志回归 + prompt 微调
```

预估：**P2.1 + P2.2** 约 3–5 天（渲染 + 感知对齐是核心）。

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

_最后更新：v2.0 验收阶段。修复 `main.gd` 重复 `_control_mode_label` 后游戏可运行。_
