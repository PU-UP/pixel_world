# P4 验收清单 — 记忆 + 反思

## 启动

```powershell
& "D:\Applications\godot\Godot_v4.7.2-stable_win64.exe" --path "D:\Projects\pixel_world\godot"
```

## 验收项

| # | 操作 | 预期 |
|---|---|---|
| E1 | F3 切 agent 模式，运行一段时间 | `data/memory/player.json` 出现记忆条目 |
| E2 | 按 **F4** 打开记忆面板 | 右侧显示最近 50 条记忆（tick / category / importance / text） |
| E3 | 累计 10 条事件或 100 tick 后 | `reflection:` 区域出现 LLM 生成的反思摘要 |
| E4 | 决策 prompt | agent 行为会参考相关记忆（非纯随机乱走） |
| E5 | 重启游戏 | 记忆从 `data/memory/player.json` 加载保留 |

## 快捷键

| 键 | 功能 |
|---|---|
| F3 | manual / agent 模式 |
| F4 | 显示 / 隐藏记忆面板 |
| F1 | 暂停 |
| F2 | 单步 tick |

## 配置

`config/runtime.yaml` → `memory` 段：

- `reflection.trigger_events` / `trigger_ticks` — 反思触发频率
- `retrieval.top_k` — 每次决策检索记忆条数
- `hud.display_limit` — 面板显示条数（默认 50）

## 备注

P4 记忆存储使用 JSON 文件（`data/memory/`），接口对齐 AGENTS.md schema，后续可换 GDSQLite。
