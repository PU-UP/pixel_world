# Pixel World

> 一个 GBA 时代像素风 (参考 Pokemon 红宝石/绿宝石) 的 2D 俯视角荒岛。
> 多个 AI 角色在同一地图上自由探索、互相交互、形成关系和故事。
> 每个角色由独立的 LLM agent 控制。

**思想参考**: [Generative Agents: Interactive Simulacra of Human Behavior](https://arxiv.org/abs/2304.03442) — Park et al., Stanford, 2023

## 状态

- ✅ **v1.0** — P0–P7 核心闭环可玩（多 agent、记忆、规划、关系、世界物品）
- 详细验收与已知限制 → [`docs/v1.0-release.md`](./docs/v1.0-release.md)
- 架构、迭代阶段、硬编码/agent 边界 → [`AGENTS.md`](./AGENTS.md)

## 环境要求

| 依赖 | 版本 / 说明 |
|---|---|
| **Godot** | **4.7.x**（推荐 4.7.2 stable，见 `.godot-version`） |
| **MiniMax API Key** | Agent 模式必需；手动模式可跳过 |
| **网络** | 访问 MiniMax OpenAI 兼容 API |
| Python 3 | 可选，仅 `tools/summarize_session.py` 日志分析 |
| GUT | 可选，单元测试框架，见 [`docs/testing-setup.md`](./docs/testing-setup.md) |

> 无 npm / pip 构建步骤；游戏本体纯 Godot + GDScript。

## 快速开始

### 1. 获取代码

保持如下目录结构（`config/`、`.env`、`data/` 必须在 `godot/` 的**上一级**）：

```
pixel_world/
├── config/           ← YAML 配置
├── .env              ← 本地创建，不进 git
├── data/             ← 运行时数据，自动创建
└── godot/
    └── project.godot ← 用 Godot 打开这个文件
```

```powershell
# 示例：克隆到任意路径
git clone <仓库URL> D:\Projects\pixel_world
cd D:\Projects\pixel_world
```

### 2. 配置 API Key

```powershell
Copy-Item .env.example .env
notepad .env
```

在 `.env` 中填入：

```ini
MINIMAX_API_KEY=sk-xxxxxxxx
# 可选覆盖（默认见 config/llm.yaml）
MINIMAX_BASE_URL=https://api.minimaxi.com/v1
MINIMAX_MODEL=MiniMax-M3
```

### 3. 安装 Godot

1. 从 [godotengine.org](https://godotengine.org/download/windows/) 下载 **Godot 4.7.x** Windows 版
2. 用 Godot **打开** `godot/project.godot`（不要只打开 `godot/` 子目录）

### 4. 运行

在 Godot 编辑器中按 **F5**，或命令行：

```powershell
& "C:\path\to\Godot_v4.7.2-stable_win64.exe" --path "D:\Projects\pixel_world\godot"
```

| 键 | 功能 |
|---|---|
| WASD / 点击 | 手动移动（手动模式） |
| **F3** | 切换 手动 ↔ Agent 模式 |
| **F1 / F2** | 暂停 / 单步 |
| **Tab** | 切换观测的 agent |
| **F4 / F5 / F6** | 记忆 / 关系+计划 / 小地图 |
| **Ctrl+R** | 重置世界（清空 tick、物品、记忆、关系） |
| **Esc** | 退出 |

Agent 模式需配置 `MINIMAX_API_KEY` 且能访问外网。

## 冒烟测试（无需 GUT）

```powershell
& "C:\path\to\Godot_v4.7.2-stable_win64_console.exe" `
  --path "D:\Projects\pixel_world\godot" `
  --headless -s res://../tests/test_smoke.gd
```

退出码 `0` 表示通过。

## 迁移到另一台 Windows 电脑

**会自动跟过去的**：git 中的代码与 `config/*.yaml`。

**不会自动跟过去的**（需手动处理）：

| 内容 | 处理方式 |
|---|---|
| `.env` | 在新机从 `.env.example` 复制并填入 API Key |
| `data/` | 若要保留记忆/日志/关系，整目录拷贝；否则留空，运行时会自动创建 |
| 未提交的本地改动 | 先 `git commit` 或连同文件夹一起拷贝 |

新机步骤：装 Godot 4.7.x → 拿到完整仓库 → 配置 `.env` → 打开 `godot/project.godot` → F5。

## 配置说明

| 文件 | 用途 |
|---|---|
| `config/runtime.yaml` | tick 速度、LLM 并发、记忆/规划/关系参数 |
| `config/agents.yaml` | agent 名单、人格、出生点 |
| `config/world.yaml` | 地图常量、物品、区域、事件 |
| `config/llm.yaml` | 模型、温度、超时、重试 |
| `.env` | API Key 与可选模型覆盖（优先级高于 yaml） |

运行时数据写入 `data/`（已在 `.gitignore` 中排除）：

- `data/logs/` — 观测日志与 LLM 调用记录
- `data/memory/` — agent 记忆（JSON）
- `data/relationships/` — agent 关系（JSON）

## 技术栈

| 维度 | 选定 |
|---|---|
| 引擎 | Godot 4.7 + GDScript |
| LLM | MiniMax Token Plan (OpenAI 兼容) |
| 美术 | 程序生成占位地形（待替换为 GBA tileset） |
| 规模 | 5 agent 同图仿真 |

## 目录速览

```
AGENTS.md         ← 项目宪法
config/           ← YAML 配置
godot/            ← Godot 工程（打开 godot/project.godot）
data/             ← 运行时数据（不进 git）
tools/            ← 维护脚本（如 summarize_session.py）
tests/            ← 冒烟测试 + GUT 单测
docs/             ← 设计文档与验收说明
```

## 许可

待定。
