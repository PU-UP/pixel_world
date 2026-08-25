# 行动原语规范 (Action Schema)

> 这是 agent 与世界的**唯一合同**。LLM 的所有输出必须能映射到这组原语之一。
> 完整定义见 `AGENTS.md` §4。

## 当前已规划原语 (P2 起使用)

| 原语 | 参数 | 占用 tick | 可中断 | 可见性 |
|---|---|---|---|---|
| `MOVE_TO` | `x, y` (瓦片坐标) | 与距离成正比 | 是 | 路径上 agent 都可见 |
| `SAY` | `to, text, tone` | 1 | 否 | `to` 指定的 agent |
| `EMOTE` | `emoji` | 0 | 是 | 视野内所有 agent |
| `OBSERVE` | `target` | 1 | 否 | 仅自己 |
| `PICK_UP` | `item_id` | 1 | 否 | 视野内 |
| `DROP` | `item_id` | 0 | 是 | 视野内 |
| `USE` | `item_id, on` | 1 | 否 | 视野内 |
| `GIVE` | `item_id, to` | 1 | 否 | 双方可见 |
| `SLEEP` | `until_tick` | 睡到该 tick | 否 | 视野内可见入睡 |
| `WAIT` | `ticks` | 指定 tick | 是 | 视野内可见"发呆" |

## 编码方式 (P2 实施)

每个原语是一个 `Action` 字典,带 discriminator:

```gdscript
# scripts/agent/actions.gd
class Action:
    var kind: String  # "MOVE_TO" | "SAY" | ...
    var params: Dictionary
    var agent_id: StringName
    var tick_issued: int
```

`executor.gd` 负责校验 + 应用 + 占用 tick + 写日志。

## 当前状态

- 已实现：`MOVE_TO` `SAY` `OBSERVE` `PICK_UP` `DROP` `USE` `GIVE` `SHARE_MAP` `WAIT` `SLEEP`
- 未实现：`EMOTE`
