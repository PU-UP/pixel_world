# Pixel World

GBA 风格 2D 俯视角荒岛仿真：多个 LLM agent 同图探索、交互、形成关系与故事。

参考 [Generative Agents](https://arxiv.org/abs/2304.03442)（Stanford, 2023）。架构见 [`AGENTS.md`](./AGENTS.md)。

## v2.0

在 v1.1 观测与决策优化之上，新增地图探索、目标与上帝视角。

- **更大地图** — 96×96 瓦片荒岛（原 64×64）
- **战争迷雾** — 每个 agent 独立探索：当前视野亮、已探索灰、未探索黑
- **上帝视角（G）** — 全图可见、无迷雾；Tab 跟随单个 agent 时恢复迷雾视角
- **目标系统** — 每名 agent 有长期目标与当前目标，注入规划/决策 prompt
- **地图共享（SHARE_MAP）** — 双方对彼此发起 SHARE_MAP 后合并已探索灰色区域
- **P8.4** — OBSERVE 超距自动靠近、重复 MOVE 跳过、SAY 长度限制

## v1.1

P8 观测与决策硬化：日志 digest、action gate、MOVE 吸附、token 节流。详见上文 v1.0 功能列表。

## v1.0

首个可玩版本（P0–P7），5 个 LLM agent 同图自主运行，支持上帝视角观测。

- **移动与寻路** — WASD / 点击移动，A* 路径规划
- **LLM 决策** — MiniMax function calling，每 tick 一个行动原语
- **多 agent 通信** — `SAY` 按距离/视线路由，并发 LLM 调度
- **记忆与反思** — JSON 记忆流，周期触发反思并落库
- **规划与关系** — 周期生成计划，agent 间亲疏/信任持久化
- **世界交互** — 物品拾取/丢弃/使用/给予，区域事件，小地图
- **观测与日志** — 实时 HUD（观察 / 决策 / 记忆 / 关系），`data/logs/` 会话记录

未实现：`EMOTE` / `SLEEP` / `WAIT`；记忆检索为关键词近似（无向量）。会话结束后运行 `python tools/digest_session.py` 生成可读摘要供外部 agent 复盘。详见 [`docs/v1.0-release.md`](./docs/v1.0-release.md)。

## 运行

**依赖**：Godot **4.7.x**（`.godot-version`）、MiniMax API Key（仅 Agent 模式）

```
仓库根/
├── config/      # YAML 配置
├── .env         # 从 .env.example 复制，填 MINIMAX_API_KEY
├── data/        # 运行时输出，首次运行自动创建
└── godot/
    └── project.godot   # ← 用 Godot 打开此文件
```

`config/` 与 `.env` 必须在 `godot/` 上一级——`Config.repo_root()` 据此解析路径。

```powershell
Copy-Item .env.example .env
# 编辑 .env：MINIMAX_API_KEY、可选 MINIMAX_BASE_URL / MINIMAX_MODEL
```

Godot 打开 `godot/project.godot`，**F5** 运行。命令行：

```powershell
godot --path godot
```

冒烟测试：

```powershell
godot --path godot --headless -s res://../tests/test_smoke.gd
```

GUT 单测见 [`docs/testing-setup.md`](./docs/testing-setup.md)。

## 操作

| 键 | 功能 |
|---|---|
| F3 | 手动 ↔ Agent |
| F1 / F2 | 暂停 / 单步 |
| Tab | 切换 agent |
| F4 / F5 / F6 | 记忆 / 关系+计划 / 小地图 |
| G | 上帝视角（全图 / 迷雾切换） |
| Ctrl+R | 重置世界 |
| ` | 隐藏 HUD |

## 配置

| 路径 | 内容 |
|---|---|
| `config/runtime.yaml` | tick、LLM 并发、记忆/规划/关系 |
| `config/agents.yaml` | agent 人格与出生点 |
| `config/world.yaml` | 地图、物品、区域、事件 |
| `config/llm.yaml` | 模型、温度、超时 |
| `.env` | API Key（覆盖 yaml 中的 base_url / model） |

运行时数据：`data/logs/`、`data/memory/`、`data/relationships/`（不进 git）。

换机部署：拷贝仓库 + `.env`；若要延续会话，一并拷贝 `data/`。

## 技术栈

Godot 4.7 · GDScript · MiniMax OpenAI 兼容 API · 5 agent 同图
