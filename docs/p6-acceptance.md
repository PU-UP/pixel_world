# P6 验收清单 — 规划 + 关系 + 性格漂移

## 启动

```powershell
& "D:\Applications\godot\Godot_v4.7.2-stable_win64.exe" --path "D:\Projects\pixel_world\godot"
```

## 验收项

| # | 操作 | 预期 |
|---|---|---|
| E1 | F3 agent 模式运行 ~100 tick | 记忆中出现 `plan` 类型条目（每 50 tick 左右重新规划） |
| E2 | 按 **F5** 打开关系面板 | 显示当前 agent 的剩余计划步骤 + 对他人的 fam/aff/trust |
| E3 | 两个 agent 多次 SAY / 同屏共处 | `data/relationships/{agent_id}.json` 中 familiarity 上升 |
| E4 | familiarity ≥ 0.35 的熟人靠近 | agent 更倾向于 SAY 打招呼（观察 decision / action log） |
| E5 | 反思触发后 | persona traits 在 HUD/agent 描述中有轻微漂移（±0.15 内） |
| E6 | Tab 切换 agent + F5 | 关系面板随选中 agent 切换 |

## 快捷键

| 键 | 功能 |
|---|---|
| F5 | 显示 / 隐藏关系 + 计划面板 |
| F4 | 记忆面板 |
| Tab | 切换 agent |
| F3 | manual / agent 模式 |

## 配置

`config/runtime.yaml`：

- `planning.trigger_ticks` — 重新规划间隔（默认 50）
- `relationships.greet_familiarity` — 视为「熟人」的阈值（默认 0.35）
- `persona_drift.max_per_trait` — 相对基线的最大漂移（默认 0.15）

## 备注

- 关系数据存 `data/relationships/{agent_id}.json`（不进 git）
- 计划写入记忆流 category=`plan`，并注入每次决策 prompt
- 同屏共处每 10 tick 微量增加 familiarity（`on_co_presence`）
