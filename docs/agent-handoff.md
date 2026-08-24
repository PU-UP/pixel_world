# Agent 交接文档 — Pixel World

> 给其他 AI/人类协作者：**当前版本摘要 + 仓库状态 + 下一阶段方向**。  
> 宪法级架构见根目录 [`AGENTS.md`](./../AGENTS.md)。

---

## 1. 当前版本快照（v2.1）

| 项 | 说明 |
|---|---|
| **引擎** | Godot 4.7.x，`godot/project.godot` |
| **地图** | 96×96 瓦片，程序化色块（非 TileMap 美术） |
| **Agent** | 5 个 LLM agent，MiniMax function calling |
| **观测** | HUD + 全员侧栏 + `data/logs/` + `tools/digest_session.py`（**无局内回放 UI**） |
| **视角** | 默认上帝全图；G 切换跟随迷雾；跟随仅 VISIBLE 显示其他 agent/物品 |

### v2.1 已交付

- 默认上帝视角：全图、全员精灵、全物品、侧栏坐标/区域/当前目标
- 跟随模式：仅选中 agent 的 VISIBLE 格显示同伴与地面物品；灰区为地形快照
- 移动：agent 互不物理阻挡；靠近停邻格；WALKING 位移不足 abort + `movement_stuck`
- `WAIT` 原语；`SHARE_MAP` 合并探索快照

### v2.0 已交付

- 战争迷雾三层、目标系统、`SHARE_MAP`、P8.4 决策硬化

### v1.1 已交付（摘要）

- 决策 gate、`resolve_move_goal`、动态 tool enum、日志 digest、token 节流

---

## 2. 代码地图（高频改动点）

```
config/           world.yaml agents.yaml runtime.yaml llm.yaml
godot/scripts/
  main.gd         入口、HUD、G 上帝视角、VISIBLE 裁剪
  player.gd       移动超时、WAIT、exploration 快照
  agent/
    decision.gd   LLM 决策 + gate + 邻格会合 redirect
    actions.gd    原语 schema / validate_in_context
    comm.gd       SAY/GIVE/SHARE_MAP 路由
    goals.gd      目标持久化
    coordinator.gd  agent 生命周期
  world/
    world.gd      地图生成与物品可见性过滤
    exploration_map.gd  探索快照 {terrain, tick}
  ui/
    fog_of_war.gd 黑 / 快照灰 / 视野亮
    minimap.gd    小地图迷雾
    camera_rig.gd 跟随 / 上帝缩放
tools/
  digest_session.py summarize_session.py reset_game.py
data/             运行时，不进 git
```

---

## 3. 仍可后置

- P2.3 世界改动后的过时快照刷新
- tileset / 向量记忆 / 日夜 / 视线遮挡

验收：启动即全图；G 后跟随仅见视野内同伴；三人靠近后能继续决策（日志可有 `movement_stuck` 但应恢复）。

---

## 4. 建议迭代顺序

P2.3（世界会变之后）→ 跑局看 anomalies / tokens。不要做局内回放 UI。

---

## 5. 验收与运维命令

```powershell
# 清运行时（含 goals）
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

_最后更新：v2.1 观察者视角 + 移动语义。_
