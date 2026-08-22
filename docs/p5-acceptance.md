# P5 验收清单 — 多 agent + 通信

## 启动

```powershell
& "D:\Applications\godot\Godot_v4.7.2-stable_win64.exe" --path "D:\Projects\pixel_world\godot"
```

Headless smoke（应能正常退出）：

```powershell
& "D:\Applications\godot\Godot_v4.7.2-stable_win64.exe" --path "D:\Projects\pixel_world\godot" --headless --quit-after 1
```

## 验收项

| # | 操作 | 预期 |
|---|---|---|
| E1 | 启动游戏 | 地图上出现 **5 个**不同颜色的 agent（explorer / scout / sage / wanderer / guardian） |
| E2 | 按 **Tab** 切换选中 | HUD 显示当前 agent 状态；选中 agent 有黄色高亮圈；相机跟随选中者 |
| E3 | F3 切 agent 模式，运行一段时间 | 5 个 agent 各自独立决策、移动；`data/logs/` 日志含不同 `agent_id` |
| E4 | 两个 agent 靠近后 | 一方 `SAY` 另一方能在 action log 看到 `heard` 记录 |
| E5 | F4 记忆面板 + Tab 切换 | 每个 agent 有独立记忆文件 `data/memory/{agent_id}.json` |
| E6 | 广播 `SAY` to=broadcast | 听觉半径内所有 agent 收到消息 |

## 快捷键

| 键 | 功能 |
|---|---|
| Tab | 切换选中 agent |
| F3 | manual / agent 模式 |
| F4 | 显示 / 隐藏记忆面板 |
| F1 | 暂停 |
| F2 | 单步 tick |
| ` | 隐藏 HUD |

## 配置

- `config/agents.yaml` — 5 个 agent 的 spawn、颜色、人格
- `config/runtime.yaml` → `agent.starting_agents: 5`、`audio_radius: 10`

## 备注

- 手动模式（F3）下 WASD/鼠标仅控制**当前选中** agent
- LLM 回调按 `meta.agent_id` 过滤，避免多 agent 共用 `LlmClient` 时串线
- `SAY` 可达性：曼哈顿距离 ≤ `audio_radius`（默认 10 格）
- LLM 客户端支持并发池（`llm.concurrency`，默认 4）；状态栏 `LLM:3/5` = 3 进行中 / 5 总排队+进行中
- 记忆面板标题与每条记录带 `[agent_id]`；Tab 切换 agent 时面板即时刷新
