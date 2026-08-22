# Pixel World

> 一个 GBA 时代像素风 (参考 Pokemon 红宝石/绿宝石) 的 2D 俯视角荒岛。
> 多个 AI 角色在同一地图上自由探索、互相交互、形成关系和故事。
> 每个角色由独立的 LLM agent 控制。

**思想参考**: [Generative Agents: Interactive Simulacra of Human Behavior](https://arxiv.org/abs/2304.03442) — Park et al., Stanford, 2023

## 状态

- ✅ **P0 工程基线** — git 仓库 + 项目宪法 `AGENTS.md` + `.env.example` + `.gitignore`
- ⏳ P1 渲染 + 单 agent 移动 — 即将开始

详细架构、迭代阶段、硬编码/agent 边界 → 见 [`AGENTS.md`](./AGENTS.md)。

## 快速开始 (P1 之后才有意义)

```bash
# 1. 装 Godot 4.3+ (https://godotengine.org)
# 2. 用 Godot 打开 godot/project.godot
# 3. 把 .env.example 复制为 .env 并填入 MINIMAX_API_KEY
# 4. F5 跑
```

## 技术栈

| 维度 | 选定 |
|---|---|
| 引擎 | Godot 4 + GDScript |
| LLM | MiniMax Token Plan (OpenAI 兼容) |
| 美术 | Open Source 像素 tileset |
| 起步规模 | 1 agent → 5 agent |

## 目录速览

```
AGENTS.md         ← 项目宪法(架构/边界/阶段/护栏)
config/           ← YAML 配置
godot/            ← Godot 4 工程(IDE 打开 godot/project.godot)
data/             ← 运行时数据(不进 git)
tools/            ← 一次性工具脚本
tests/            ← GUT / gdUnit4 测试
docs/             ← 设计文档
```

## 许可

待定。
