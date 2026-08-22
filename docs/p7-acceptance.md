# P7 验收清单 — 地图物品 + 区域 + 小地图

## 启动

```powershell
& "D:\Applications\godot\Godot_v4.7.2-stable_win64.exe" --path "D:\Projects\pixel_world\godot"
```

## 验收项

| # | 操作 | 预期 |
|---|---|---|
| E1 | 启动游戏 | 地图上可见彩色圆点（地面物品：driftwood、seashell 等） |
| E2 | 按 **F6** | 右上角出现 96×96 鸟瞰小地图，黄点 = 5 个 agent |
| E3 | agent 靠近物品并 PICK_UP | action log 显示 `pickup got ...`；HUD `inv=` 有物品；地面圆点消失 |
| E4 | DROP 原语 | 物品落回当前格，圆点重现 |
| E5 | 观测文本 | 含 `region=South Beach` 等区域名 + `items: driftwood@(x,y)` |
| E6 | `config/world.yaml` | 可改 `ground_items` / `regions` / `items` 无需改代码 |
| E7 | 运行 ~90 tick | 观测出现 `event: ...`（区域/全岛事件） |
| E8 | OBSERVE 附近 agent 或物品 | action log 显示详细描述 |
| E9 | HUD 状态栏 | 显示 `tok:N`（本局累计 token） |
| E10 | agent GIVE 物品给邻近 agent | giver `inv` 减少；receiver `received ...`；F5 关系略升 |
| E11 | USE `berry_bush`（consumable） | action log 显示 use 文案；`inv` 中 berry 消失 |
| E12 | F6 小地图 | 除黄点 agent 外，可见彩色 2×2 物品点 |
| E13 | `data/logs/{session}.jsonl` | 含 `world_event` 行（event_id、text、tick） |

## 快捷键

| 键 | 功能 |
|---|---|
| F6 | 鸟瞰小地图 |
| F5 | 关系 + 计划 |
| F4 | 记忆 |
| Tab | 切换 agent |

## 配置

- `config/world.yaml` → `items`、`ground_items`、`regions`、`item_pickup_radius`

## 备注

- P7 仍用占位色块地形；正式 tileset 可后续替换 `world.gd` 渲染
- 已实现原语：`MOVE_TO`、`SAY`、`PICK_UP`、`DROP`、`OBSERVE`、`USE`、`GIVE`
- Token 统计：HUD `tok:N` + `data/logs/{session}_summary.json`