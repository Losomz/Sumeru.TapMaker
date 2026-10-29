# 通用音频 Kit

`require("sumeru.toolkit.audiokit")` 返回通用音频管理器，负责缓存 `Sound`、复用音效音源池、按规则错开或吞掉同名音效，以及切换循环 BGM。

```lua
local AudioKit=require("sumeru.toolkit.audiokit")
local audio=AudioKit.new({
    music=tracks,
    sounds=effects,
    poolSize=12,
    musicGain=.28,
    pools=poolKit,              -- 可选：登记进 PoolKit 统一统计
    rules={
        death={gain=.3,gap=.05,queue=3,voices=4,falloff=.8},
    },
})

audio:SetSettings({music=true,sfx=true})
audio:PlayEffect("shot")
audio:SwitchBGM("battle")
audio:Update(dt)               -- 每帧调用：冷却、音源回收、错开起播
```

## 设计

- `Sound` 按路径缓存，只加载一次。约十几个短音频由引擎资源缓存持有，不做淘汰；释放后再加载反而会卡顿。
- 音效音源由 `toolkit/poolkit` 的 `ObjectPool` 管理，`prewarm` 与 `limit` 都等于 `poolSize`（默认 12）：初始化一次建好，运行中不再新建。每路音源的槽位标记原地复用，播放时不新建表。`Update` 把已播完的音源交换移出播放表并放回池。
- 池满时取音源的顺序：先复用已播完、尚未回收的音源；仍没有时，**只有新声音优先级严格高于**最低优先级的那一路才抢占（同级取最旧）。同级新声音直接吞掉，不掐断正在播的声音。
- BGM 使用独立 `SoundSource`，不占用音效池。
- `IsEffectPlaying(name)` 查询指定事件音效是否仍在播放或等待错开起播；`StopEffect(name)` 只停止该事件并清掉它的等待记录。业务可据此等待一次性提示结束，或在离开页面时收尾。
- `Track` 和 `Effect` 是兼容入口，分别等价于 `SwitchBGM` 和 `PlayEffect`。
- 复用播放源时显式传入 `frequency=0`，避免上一次播放的频率影响下一条音效。

## 播放规则 `rules`

规则先按事件名查找，再按实际声音名（`aliases` 映射后的名称）查找。同名计数和错开按 key 进行，key 缺省为事件名，可用调用参数 `cooldownKey` 指定。

| 字段 | 含义 | 缺省 |
|---|---|---|
| `gap` | 同 key 最小起播间隔（秒）。间隔内的新请求排到上一条之后 `gap` 起播 | 不设时沿用冷却丢弃 |
| `queue` | 同 key 最多等待条数，超过吞掉 | 2 |
| `maxDelay` | 最长推迟（秒），超过吞掉，避免声音与画面脱节 | 0.2 |
| `voices` | 同 key「仍在出声 + 等待中」上限，超过吞掉 | 不限，只受总池限制 |
| `falloff` | 叠加衰减：起播时同 key 每多一路仍在出声，音量乘一次该系数 | 1，不衰减 |
| `gain / priority / cooldown` | 音量、优先级、冷却，与下方默认表等价 | 默认表 |

- 调用参数 `force=true`（以及 `boss_spawn`）跳过冷却、错开和同名上限。调用参数中的 `gain`、`priority`、`cooldown` 优先于规则。
- 等待记录同样由 `ObjectPool` 复用，容量为 `pendingSize`（默认 16），池满时吞掉。到点后在 `Update` 中起播并放回池。
- 未配置 `gap` 的声音保持冷却限频：冷却期内的新请求直接丢弃，缺省冷却 0.08 秒。

框架默认表可以通过同名配置合并覆盖，未覆盖的项保持默认值：

| 配置 | 默认值 |
|---|---|
| `aliases` | `victory→ui`、`defeat→alarm`、`tower_hit→hit`、`boss_spawn/boss_buff→boss` |
| `priorities` | Boss 登场 100、Boss 90、爆炸 80、警报 70、击杀 60、受击 40、射击／电／火 20，其余 10 |
| `gains` | 射击 0.2，Boss 相关 0.5；其余用 `effectGain`（默认 0.5） |
| `cooldowns` | 射击／电／火 0.16 秒，Boss 相关 0.36 秒 |

## PoolKit 与统计

- 传入 `pools`（已注册的 PoolKit System）时，音源池与等待池以 `poolName:voices`、`poolName:pending` 登记（`poolName` 默认 `audio`）。调试面板读取 `PoolKit:Stats()` 即可看到使用中、峰值、新建与满额次数。
- 登记前先释放同名旧池，因为音源绑定本实例的场景。不传 `pools` 时建本地池，用法不变。
- `GetStats()` 返回 `played`（起播）、`staggered`（错开排队）、`dropped`（吞掉，含规则超限与无音源可用）、`stolen`（抢占），以及当前和峰值音源数、等待数。每次调用新建快照表，只供调试面板低频读取。
