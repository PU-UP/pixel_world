# Agent 交接文档 — Pixel World

> 给其他 AI/人类协作者：**当前版本摘要 + 仓库状态 + 下一阶段方向**。  
> 宪法级架构见根目录 [`AGENTS.md`](./../AGENTS.md)。

---

## 1. 当前版本快照（v2.4）

| 项 | 说明 |
|---|---|
| **引擎** | Godot 4.7.x，`godot/project.godot` |
| **地图** | 96×96 瓦片，程序化色块（非 TileMap 美术） |
| **Agent** | 5 个 LLM agent，MiniMax function calling |
| **观测** | HUD + 全员侧栏 + `data/logs/` + `tools/digest_session.py`（**无局内回放 UI**）；状态栏标 LOS/光圈/续局 |
| **视角** | 默认上帝全图；G 切换跟随迷雾；跟随仅 VISIBLE 显示其他 agent/物品 |
| **操控** | 默认自主；F3 切手动；续局记住上次 F3 |
| **续局** | `data/saves/world.json`；关游戏再开接续世界。Ctrl+R 开新局 |
| **感知** | 视野半径 + 树/山视线遮挡；SAY 仍按听觉半径 |

### v2.4 已交付

- 新开局默认 `control.mode: agent`（F3 仍可切手动）
- 状态栏 `规则:LOS·光圈·续局/新局`；手动时提示 `F3自主`
- 记忆检索：丢弃 tick 大于当前时钟的条目；同 tick 的 plan/reflection 只留最新；tick=1 簇降权
- 日志 `observer_state`；Ctrl+R 取消在途 LLM（epoch），避免旧决策写进新局

### v2.3 已交付

- 树、山挡住视线（`config/runtime.yaml` → `agent.los` / `los_block`）
- 迷雾 VISIBLE、观察文本、同伴精灵、地面物品都走 LOS
- 上帝视角用浅色标出 **Tab 选中角色的当前视野**（树后为暗缺口）；侧栏写可见/遮挡/超距
- SAY / GIVE 仍只按听觉半径，隔着树也能听到

### v2.2 已交付

- 关闭窗口 / Esc 写世界存档；每 N tick 自动存（`config/runtime.yaml` → `save`）
- 读档恢复 tick、地面物品、事件进度、agent 位置/背包/迷雾快照、目标、剩余计划、性格漂移、选中角色、上帝/跟随
- 不恢复进行中的行走路径与 inflight LLM（读档后 idle 在存档格）
- Ctrl+R 与 `python tools/reset_game.py` 同时清除记忆/关系/目标/世界存档

### v2.1 已交付

- 默认上帝视角：全图、全员精灵、全物品、侧栏坐标/区域/当前目标
- 跟随模式：仅选中 agent 的 VISIBLE 格显示同伴与地面物品；灰区为地形快照
- 移动：agent 互不物理阻挡；靠近停邻格；WALKING 位移不足 abort + `movement_stuck`
- `WAIT` 原语；`SHARE_MAP` 合并探索快照

### v2.0 已交付

- 战争迷雾三层、目标系统、`SHARE_MAP`、P8.4 决策硬化

---

## 2. 代码地图（高频改动点）

```
config/           world.yaml agents.yaml runtime.yaml llm.yaml
godot/scripts/
  main.gd         入口、HUD、G 上帝视角、VISIBLE 裁剪、读档/存档
  player.gd       移动超时、WAIT、exploration 快照、位置/背包序列化
  agent/
    decision.gd   LLM 决策 + gate + 邻格会合 redirect
    actions.gd    原语 schema / validate_in_context
    comm.gd       SAY/GIVE/SHARE_MAP 路由
    goals.gd      目标持久化
    coordinator.gd  agent 生命周期 + capture/apply_world
  world/
    world.gd      地图生成、物品可见性、has_line_of_sight
    exploration_map.gd  探索快照 {terrain, tick}
    save_game.gd  单槽 world.json
    clock.gd      restore_tick（不补发错过的 tick）
    state.gd / events.gd  地面物品与事件进度
  ui/
    fog_of_war.gd 黑 / 快照灰 / 视野亮
    minimap.gd    小地图迷雾
    camera_rig.gd 跟随 / 上帝缩放
tools/
  digest_session.py summarize_session.py reset_game.py
data/             运行时，不进 git（含 saves/）
```

---

## 3. 仍可后置

- P2.3 世界改动后的过时快照刷新
- tileset / 向量记忆 / 日夜 / SLEEP

验收 v2.4：无存档开局应直接自主跑，不必先 F3；状态栏能看出 LOS/光圈/新局或续局。已有 `world.json` 会记住上次的 F3 状态。

---

## 4. 建议迭代顺序

P2.3（世界会变之后）→ 日夜/SLEEP → 跑局看 anomalies / tokens。不要做局内回放 UI。

---

## 5. 验收与运维命令

```powershell
# 清运行时（含 goals + 世界存档）
python tools/reset_game.py
python tools/reset_game.py --logs

# 局后分析
python tools/summarize_session.py
python tools/digest_session.py data/logs/<session>.jsonl
```

---

## 6. 不要做的事

- 不要加 **局内时间轴回放 UI**（用 `data/logs/` + digest 给外部 agent 复盘）
- 不要把 `data/`、`.env` 提交 git
- 大幅改架构前先更新 `AGENTS.md`

---

_最后更新：v2.4 观察者默认可感 + 记忆时钟卫生。_
