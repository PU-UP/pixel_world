# Pixel World — 项目宪法（Project AGENTS.md）

> 这是项目根 `AGENTS.md`，是给所有 AI/人类协作者读的"宪法"。
> 它定义：**架构、硬编码边界、agent 权限边界、迭代阶段、文件/目录约定、协作流程**。
> 在做大幅改动前先读它；改它时先讨论。

---

## 0. 项目愿景

一个**类 GBA 时代的像素风**（参考 Pokemon 红宝石/绿宝石）2D 俯视角游戏：
- 地图是**荒岛**（森林、沙滩、山地、洞穴、水域、废墟）
- 多个**AI 角色**在同一张地图上**自由探索、互相交互、形成关系和故事**
- 每个角色由**独立的 LLM agent** 控制
- 玩家既可**观察**，也可在特定节点**干预**（可选：进入世界成为第 N+1 个 agent）

**思想参考**：
- *Generative Agents: Interactive Simulacra of Human Behavior* — Park et al., Stanford, 2023（"AI 小镇"）
- 核心三件套：**Memory Stream**（记忆流）+ **Reflection**（反思）+ **Planning**（规划）

---

## 1. 核心设计原则：什么硬编码、什么交给 Agent

这是整个项目最重要的边界。**模糊的边界 = 不可控的世界**。下面所有"硬编码"项都必须由代码明确定义语义、参数和接口；"Agent 决策"项才能交给 LLM。

### 1.1 必须由代码硬实现（确定性 / 可观测 / 可测试）

| 类别 | 具体机制 | 为什么必须硬编码 |
|---|---|---|
| **渲染** | 瓦片地图、精灵图、动画状态机、相机跟随、UI | 美术资产与渲染管线是工程基座，不应让 LLM 决定 |
| **物理与碰撞** | 瓦片碰撞、AABB、阻挡、推挤、传送门 | 一旦"软"控制，世界会破图 |
| **寻路** | A* / HPA* / 导航网格 | 必须可重复、可解释、可调试 |
| **时间系统** | 游戏内时钟（tick）、日夜循环、季节（可选） | 所有调度、记忆衰减、计划粒度都依赖统一时间 |
| **感知系统** | 视野半径、听觉半径、可见性（树/墙遮挡）、事件可见性 | 决定 agent 能"看到/听到"什么，是信息公平性的根 |
| **记忆基础设施** | 存储 schema、写入/检索 API、重要性评分公式、衰减函数、向量化索引 | agent 不能自由篡改"已经发生的事"，只能写新条目 |
| **反思基础设施** | 反思触发条件、反思 prompt 模板、生成条目的合法 schema | 反思必须能落库并被检索，否则就是一次性输出 |
| **行动原语（Action Primitives）** | `MOVE_TO(x,y)`、`SAY(to,text)`、`EMOTE(emoji)`、`PICK_UP(item)`、`USE(item,target)`、`OBSERVE(target)` | 这是 agent 与世界的**唯一**受控接口（function calling） |
| **行动执行器** | 原语的具体实现、合法性校验、失败回退、占用时间 | 决定一次"说话"或"走一步"要花多少 tick、能否被中断 |
| **通信路由** | 消息可达性（距离/视线）、广播规则、私聊规则 | 防止 agent 用"心电感应"破坏公平性 |
| **世界状态机** | 物品/资源/地块/建筑/事件的权威状态 | 唯一的真相源；agent 只能通过 action 修改 |
| **Tick 调度** | 谁在何时被唤醒、每帧多少 LLM 调用、并发上限 | 决定成本、可玩性、可调试性 |
| **LLM 调用层** | prompt 模板、token 预算、重试、错误兜底、缓存 | 决定 LLM 的"性格"和稳定性 |
| **观测日志** | 每个 agent 的每一步：看到什么、想到什么、决定什么、做了什么 | 这是后期 debug / 评估的命脉 |
| **存档/读档** | 序列化记忆、世界状态、计划 | 必须能重放和回滚 |
| **安全护栏** | 危险动作的二次校验、prompt 注入防御、内容过滤 | 防止 agent 越权或生成不当内容 |

### 1.2 可以交给 Agent 决策（创造性 / 个性化）

| 类别 | 决策内容 | 约束 |
|---|---|---|
| **当前目标** | agent 在 N 个 tick 内想达成什么 | 必须是合法 action 的组合 |
| **行动计划** | 路径点序列、动作顺序 | 必须用行动原语表达 |
| **对话内容** | 说什么、语气、话题 | 受 `SAY` 原语约束 |
| **反思内容** | 对近期事件的总结、对自身/他人的评价 | 必须落到结构化 schema |
| **关系评估** | 对其他 agent 的好恶/亲疏/信任 | 写到记忆流的派生字段 |
| **性格漂移** | 在硬编码人格基线上的微调 | 受基线约束，不能 180° 翻转 |
| **物品偏好** | 拿/用/丢什么 | 仍要走 action 原语 |
| **探索兴趣** | 想去地图哪块 | 走寻路接口 |
| **情绪状态** | 当前心情 | 写入状态字段，影响后续 prompt |

> **关键原则**：agent 永远只能**通过 action 原语**改变世界；它的"思考"是**对自身记忆和状态**的写操作，对世界状态的写操作必须经过校验。

### 1.3 边界上的灰色地带 — 走"配置而非硬编码"路径

例如：
- 行动原语的成本（每步多少 tick）
- 反思触发频率（每 N 个事件 / 每 M 个 tick）
- 记忆保留天数
- LLM 温度

这些走 `config.yaml`，**不是写死在代码里**。这样既灵活又可重现。

---

## 2. 系统架构

### 2.1 模块图（分层）

```
┌─────────────────────────────────────────────────────────────┐
│                   Game Loop (Tick Scheduler)                 │
└─────────────────────────────────────────────────────────────┘
            │
            ├──► World    (地图、物理、世界状态、tick 推进)
            ├──► Renderer (瓦片、精灵、UI — 引擎层)
            ├──► Logger   (观测日志、metrics、replay)
            │
            └──► Agent Runtime  (一个 agent 一个)
                   │
                   ├── Perception    (看到/听到什么)
                   ├── Memory Stream (短期 + 长期 + 向量索引)
                   ├── Reflection    (周期触发, 压缩记忆)
                   ├── Planning      (生成高层计划)
                   ├── Decision      (LLM 一次 tick 调用的核心)
                   └── Action Exec   (把计划翻译为原语并执行)
```

### 2.2 一次 Tick 的数据流（核心循环）

```
for each agent in parallel (with throttle):
  1. 感知: 读世界状态 → 生成"当前观察" prompt 片段
  2. 检索记忆: 重要记忆 + 相关记忆 + 近期反思 → prompt 片段
  3. 决策:  LLM(Persona + Observations + Memories + Plans) → 1 个原语
  4. 执行:  Action Executor 校验 + 占用 tick + 推进世界状态
  5. 记录:  观测日志 + 记忆流 append
每 K 个 tick: 触发反思
每 M 个 tick: 触发再规划
```

**关键约束**：
- 一次 tick，agent **只能选一个原语**。如果 LLM 想"走过去再说话"，必须拆成两步。
- 行动原语是**同步执行**的，下一 tick 才会感知到结果（避免 agent"预知未来"）。
- LLM 调用**批处理 + 限流**（默认 5 req/s 可调）。

---

## 3. 项目结构（git 工程布局）

```
D:\Projects\pixel_world\
├── AGENTS.md                  ← 本文件
├── README.md
├── LICENSE
├── pyproject.toml             ← Python 项目元数据 / 依赖
├── .gitignore
├── .env.example               ← LLM API key 等
├── config/
│   ├── world.yaml             ← 地图、初始 NPC、物品、世界常量
│   ├── agents.yaml            ← agent 名单、人格基线、出生点
│   ├── llm.yaml               ← 模型、温度、token、限流
│   └── runtime.yaml           ← tick 速度、反思/规划频率、调试开关
│
├── assets/                    ← 美术/音效
│   ├── tilesets/
│   ├── sprites/
│   ├── ui/
│   └── audio/
│
├── data/                      ← 运行时生成的数据(不进 git)
│   ├── saves/                 ← 存档
│   ├── memory/                ← agent 记忆库(SQLite + 向量)
│   ├── logs/                  ← 观测日志
│   └── replays/
│
├── src/
│   ├── engine/                ← 引擎层(Pygame/Godot 绑定)
│   │   ├── game.py
│   │   ├── renderer.py
│   │   ├── camera.py
│   │   ├── input.py
│   │   └── ui.py
│   │
│   ├── world/                 ← 世界层
│   │   ├── map.py             ← 瓦片地图
│   │   ├── tiles.py
│   │   ├── physics.py
│   │   ├── pathfinding.py     ← A*
│   │   ├── clock.py           ← tick / 日夜
│   │   ├── events.py          ← 事件总线
│   │   └── state.py           ← 权威世界状态
│   │
│   ├── agent/                 ← agent 运行时
│   │   ├── persona.py
│   │   ├── perception.py
│   │   ├── memory/
│   │   │   ├── stream.py      ← 记忆流
│   │   │   ├── store.py       ← SQLite
│   │   │   ├── vector.py      ← 向量索引
│   │   │   └── importance.py
│   │   ├── reflection.py
│   │   ├── planning.py
│   │   ├── decision.py        ← LLM 决策核心
│   │   ├── actions.py         ← 行动原语定义
│   │   └── executor.py        ← 原语执行器
│   │
│   ├── llm/                   ← LLM 适配层
│   │   ├── client.py          ← OpenAI / Ollama / Anthropic 统一接口
│   │   ├── prompts/           ← 模板(可版本化)
│   │   ├── parser.py          ← 解析 LLM 输出为 action
│   │   └── guard.py           ← prompt 注入防御
│   │
│   ├── observability/         ← 观测 / 评估
│   │   ├── logger.py
│   │   ├── metrics.py
│   │   └── replay.py
│   │
│   └── main.py                ← 入口
│
├── tools/                     ← 一次性工具脚本
│   ├── seed_agents.py         ← 创建 agent
│   ├── inspect_memory.py      ← 查看某个 agent 的记忆
│   └── replay_session.py      ← 重放某次会话
│
├── tests/
│   ├── test_pathfinding.py
│   ├── test_actions.py
│   ├── test_memory.py
│   └── test_simulation.py     ← 端到端: 多 agent 跑 N tick
│
└── docs/
    ├── architecture.md        ← 详细架构(本文件扩展)
    ├── action_schema.md       ← 行动原语规范
    └── design_notes.md        ← 设计取舍记录
```

---

## 4. 行动原语规范（Action Schema）

> 这是 agent 与世界的**唯一合同**。LLM 的所有输出必须能映射到这组原语之一。

```yaml
actions:
  - MOVE_TO:     { x: int, y: int }              # 沿 A* 路径走,占用 N tick
  - SAY:         { to: agent_id | "broadcast", text: str, tone: str }  # 占用 1 tick
  - EMOTE:       { emoji: str }                  # 占用 0 tick
  - OBSERVE:     { target: agent_id | object_id } # 主动观察,获取额外信息
  - PICK_UP:     { item: item_id }
  - DROP:        { item: item_id }
  - USE:         { item: item_id, on: target }    # 用物品
  - GIVE:        { item: item_id, to: agent_id }
  - SLEEP:       { until: tick }                 # 时间跳过
  - WAIT:        { ticks: int }                  # 原地等待
```

**每个原语必须定义**：
- 参数 schema（JSON Schema）
- 占用 tick 数
- 失败条件（例如目标不可达 → 静默失败 + 记录）
- 是否可被中断
- 是否对其他 agent 可见（影响其感知）

---

## 5. 关键算法与公式

### 5.1 记忆重要性评分

```
importance = base_importance(category)
           + 0.3 * novelty_decay(recency)
           + 0.2 * emotional_intensity
           + 0.2 * social_relevance (mentions other agents?)
           + 0.1 * goal_relevance (relates to current plan?)
```

- `base_importance` 由事件类别决定（受伤/被攻击=0.9, 捡到钱=0.5, 路过树=0.05）
- 重要性 > 0.7 的记忆**永远不衰减**（人格级记忆）

### 5.2 记忆检索（每次决策前）

```
top_k = retrieve(
  query = current_observation_embedding,
  memories = all_memories,
  k = 50,
  filters = { time_window: last 3 days, recency_weight: 0.3 }
)
```

混合排序：`0.7 * cosine_similarity + 0.3 * recency_score + 0.2 * importance`

### 5.3 反思触发

每 K 个事件 或 每 M 个 tick（默认 K=10, M=100，可调）：
1. 取出最近 N 条记忆
2. 问 LLM：*"基于这些事件,你对自己/他人/世界形成了什么新认识?"*
3. 把答案作为新记忆写入，**类型 = reflection**

### 5.4 计划生成

每 P 个 tick（默认 P=50）：
1. 问 LLM：*"你今天/接下来想做什么? 给出一个 5-7 步的计划"*
2. 存为 `plan` 类型记忆
3. 每次决策时把当前 plan 的剩余步骤作为 prompt 片段喂回去

---

## 6. 迭代阶段（建议节奏）

| 阶段 | 目标 | 验收 | 估时 |
|---|---|---|---|
| **P0 - 工程基线** | git init + 项目结构 + CI/测试框架 | `pytest` 通过空项目 | 半天 |
| **P1 - 渲染 + 单 agent 移动** | 能在地图上画一个 sprite,键盘控制移动,带相机 | 能走能看 | 2 天 |
| **P2 - 寻路 + 行动原语骨架** | A*、原语定义、键盘→原语映射 | 鼠标点哪走哪 | 2 天 |
| **P3 - LLM 决策闭环** | 单 agent 接 LLM,一次决策→一个原语→执行 | agent 能"想"去哪 | 3 天 |
| **P4 - 记忆 + 反思** | SQLite + 向量 + 反思触发 | agent 记得"昨天见过谁" | 3 天 |
| **P5 - 多 agent + 通信** | N 个 agent 跑同一世界,`SAY` 可达 | 两人能对话 | 3 天 |
| **P6 - 规划 + 关系** | Planning + 关系字段 + 性格漂移 | 看到熟人主动打招呼 | 3 天 |
| **P7 - 完整地图 + 物品 + 事件** | 荒岛美术、物品、可交互物体、世界事件 | demo 可玩 | 5 天 |
| **P8 - 观测/回放/护栏** | 观测日志、重放工具、prompt 注入防御 | 可调试 | 2 天 |

总计约 **25-30 天**(单人)。

---

## 7. 配置约定（config/*.yaml）

所有"魔法数字"必须在配置中，**代码里不出现裸数字常量**。示例：

```yaml
# config/runtime.yaml
tick:
  duration_ms: 500
  llm_concurrency: 4

memory:
  importance_threshold_for_permanent: 0.7
  reflection:
    trigger_events: 10
    trigger_ticks: 100
    lookback: 50
  retrieval:
    top_k: 50
    recency_weight: 0.3

llm:
  provider: openai            # openai | ollama | anthropic
  model: gpt-4o-mini
  temperature: 0.7
  max_tokens: 400
  timeout_s: 20
  retry: 2

agent:
  max_ticks_per_decision: 1   # 一次决策最多执行几个原语
  perception_radius: 6
  audio_radius: 10
  starting_agents: 5
```

---

## 8. 协作与工程实践

- **Git 流程**：trunk-based, 短分支, 每天 rebase, PR 描述贴 demo 截图/日志
- **Conventional Commits**：`feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`
- **测试**：核心系统(寻路/原语/记忆/时间)必须有单元测试
- **观测优先**：每个 PR 必须包含一次"跑 100 tick 观察"的日志
- **Prompt 版本化**：`src/llm/prompts/*.j2` 进 git, 改 prompt 算 feat
- **不可提交**：`data/`, `.env`, 任何 API key, 任何 LLM 原始回复缓存

---

## 9. 安全与护栏

- **Action 校验**：每个原语执行前 schema 校验 + 合法性校验
- **Prompt 注入防御**：系统提示中禁止出现"忽略以上指令"等元指令,工具描述中禁止让 LLM 输出违反 schema 的内容
- **内容过滤**：对话内容过一遍敏感词;不当内容落地为 `rejected` 事件
- **资源上限**：单 agent 单次 LLM 调用 token 上限 / 总 tick 上限 / 物品数量上限
- **可解释性**：每次决策必须记录 prompt + raw output + parsed action, 便于回放

---

## 10. 待确认的关键决策

> 在动手 P1 之前,以下决策需要 owner 拍板。AI 助手会就这些提问,owner 一旦定下就写进本文件作为"已决议"。

1. **引擎**: Godot 4 (GDScript/C#) / Pygame (Python) / Unity (C#) / 其他
2. **LLM**: OpenAI / Anthropic / Ollama 本地 / 混合
3. **美术资源**: 自制 / 用 free tileset / 用 AI 生成占位 / 混用
4. **初始 agent 数**: 3 / 5 / 10
5. **玩家角色**: 旁观者 / 操控一个 agent / 可切换
6. **地图大小**: 32x32 起步 / 64x64 / 更大
7. **运行模式**: 本地单机 / 多机联网 / 仅服务器渲染

---

_本文件由项目所有者维护,任何架构级修改必须更新本文件。_
