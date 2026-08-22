# P3 验收清单 — LLM 决策闭环

## 启动

```powershell
& "D:\Applications\godot\Godot_v4.7.2-stable_win64.exe" --path "D:\Projects\pixel_world\godot"
```

或 Godot 编辑器打开 `godot/project.godot` → F5。

## 前置

- [ ] 复制 `.env.example` 为 `.env`，填入 `MINIMAX_API_KEY`
- [ ] headless 检查通过：
  ```powershell
  & "D:\Applications\godot\Godot_v4.7.2-stable_win64_console.exe" --path "D:\Projects\pixel_world\godot" --headless --quit-after 1
  ```

## 验收项

| # | 操作 | 预期 |
|---|---|---|
| E1 | 默认 `manual` 模式（`config/runtime.yaml` → `control.mode: manual`） | WASD / 鼠标点击可移动，与 P2 一致 |
| E2 | 按 **F3** 切到 `agent` 模式 | HUD 显示 `mode:AGENT`；WASD/鼠标不再响应 |
| E3 | 配置 API key 后，agent 模式运行 | agent 自主 `MOVE_TO` 并沿 A* 行走 |
| E4 | 查看 HUD `decision:` 行 | 可见 LLM 输出与解析后的 action |
| E5 | 查看 `data/logs/*.jsonl` | 每 tick 决策有完整记录 |
| E6 | 删除/留空 API key，agent 模式 | HUD 显示 `LLM:no-key` / decision 报错，不崩溃；F3 切回 manual 仍可用 |
| E7 | **F1** 暂停 | 时钟停止，无新 LLM 请求 |

## 配置调参

| 文件 | 键 | 作用 |
|---|---|---|
| `config/runtime.yaml` | `tick.hz` | 游戏 tick 频率 |
| `config/runtime.yaml` | `control.mode` | 启动默认模式 `manual` / `agent` |
| `config/llm.yaml` | `model`, `temperature` | LLM 参数 |
| `config/agents.yaml` | `persona`, `biography` | agent 人格 |

## 快捷键

| 键 | 功能 |
|---|---|
| F1 | 暂停 / 继续 |
| F2 | 单步 tick |
| F3 | 切换 manual / agent 模式 |
| Tab | 切换观测 agent（P3 仅 1 个） |
| ` | 显示 / 隐藏 HUD |
| Esc | 退出 |
