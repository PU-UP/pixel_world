# P2 验收清单 — A* 寻路 + 行动原语骨架

> P2 = "鼠标点哪走哪 + `MOVE_TO` 原语可被 LLM 调用"
> 估时 2 天。P3 LLM 决策闭环的前置依赖。

## 必备验收项

### 视觉
- [ ] 玩家头顶画出当前**路径**(小黄点串) + **目标点**(红色 X)
- [ ] HUD 4 段式面板继续工作, `AgentLabel` 多出 `state=WALKING/IDLE  q=N` 字段

### 交互 — 移动
- [ ] **鼠标点击地图任意位置**: 玩家**沿 A* 最短路径**走过去, 不穿墙/水/山/树
- [ ] 点击不可达的位置(海/山/树): action 被打成 `reject` 并写日志, 不崩
- [ ] **WASD/方向键**: 每按一下走 1 瓦片(传统 RPG 节奏), 不可走方向静默忽略
- [ ] 行走中再点新位置: 新目标**追加到队列**, 走完当前段自动接
- [ ] 行走中按 WASD: 不响应(避免路径冲突, 走完才接收)
- [ ] F1/F2/` `/Tab/ESC P1.5 全部仍工作

### 工程
- [ ] `scripts/world/pathfinding.gd` — A* 实现, 4 方向, 曼哈顿启发
- [ ] `scripts/agent/actions.gd` — 原语常量 + schema + validate() + tick_cost() + factory
- [ ] `scripts/agent/actions.gd::IMPLEMENTED_KINDS` 当前 = `["MOVE_TO"]` (P3 会扩)
- [ ] `player.gd` 状态机 `IDLE → WALKING → IDLE`, 行动通过 `_action_queue` 排队
- [ ] `main.gd::click_move` 输入接通, WASD 同样走队列
- [ ] `tests/test_pathfinding.gd` 跑通 7 项 A* 测试
- [ ] `tests/test_smoke.gd` 扩展到 28+ 项, 覆盖 actions/queue/state 接口

## 验证方法

### A* 单测(独立, 7 项)

```powershell
cd D:\Projects\pixel_world
godot --headless --path godot -s tests/test_pathfinding.gd
```

期望:
```
[OK]   test1: start==goal -> [start]
[OK]   test2: straight line, length=6
[OK]   test3: unreachable (water) -> []
[OK]   test4: detour around tree wall, length=...
[OK]   test5: unreachable start auto-snapped to neighbor, starts at ...
[OK]   test6: 64x64 diag path, length=128 time=<500ms
[OK]   test7: all-mountain, limited path, length=...
================================
P2 pathfinding test: 7 passed, 0 failed
================================
```

### Smoke test(P1 + P1.5 + P2, 28+ 项)

```powershell
godot --headless --path godot -s tests/test_smoke.gd
```

末尾应该是:
```
================================
P1 + P1.5 + P2 smoke test: 28+ passed, 0 failed
================================
```

### GUI 验证

```powershell
godot --path godot
# F5
```

- 红色玩家在岛上
- 头顶: 当前路径(黄点)+ 目标点(红 X)
- 鼠标点远处(海对岸) -> 玩家沿路径走(可能到海边就 reject, 因为海不可走)
- 鼠标点草地另一端 -> 走大弧线
- 鼠标点山/树/水 -> 玩家不动 + HUD ActionLog 显示 `reject`
- WASD 走一格一格
- 走的过程中再点新位置 -> 玩家会走到新目标

## P2 之后

进入 **P3 — LLM 决策闭环**:
- LLM client (`scripts/llm/client.gd` HTTPRequest → MiniMax)
- prompt 模板: 拼 persona + observation + memory + plans
- 把 LLM 的 `function_call` 输出直接灌入 `player.enqueue_action()`
- HUD 看到 `decision` 类型的 action_log 条目(就是 LLM 决策原文)
- F1 暂停 + Tab 切 agent + `enqueue_action` 一气呵成, 让玩家真正"看着 AI 思考"
