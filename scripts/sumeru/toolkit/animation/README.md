# 通用动画 kit

`require("sumeru.toolkit.animation")` 提供纯 Lua 播放接口，不依赖引擎、UI、敌人或存档服务。

| 类 | 作用 |
|---|---|
| `Animation` | 基类、播放进度、暂停与空动作；可继续派生 |
| `SequenceAnimation : Animation` | 按帧率选帧，循环或停在终帧 |
| `HitFeedbackAnimation : Animation` | 覆盖层闪白、短停、缩放和硬直免疫 |
| `Player` | 用枚举 ID 绑定实例，主动作与覆盖层共用接口 |

```lua
local Kit=require("sumeru.toolkit.animation")
local Id=require("game.animation.AnimationId")
local player=Kit.Player.new()
player:Bind(Id.Walk,Kit.SequenceAnimation.new(walkClip))
player:Bind(Id.Hit,Kit.HitFeedbackAnimation.new(hitFeedback),true)
player:Play(Id.Walk,{revision=record.revision})
player:Seek(record.elapsed)
player:Play(Id.Hit) -- 不替换当前主动作
local pose=player:Sample() -- frame / source / index / count / feedback
```

`Play` 对相同动作和相同修订号幂等。重播使用 `restart=true`；状态转换使用新修订号。`Seek` 读取已有模拟时间，不触发进入回调、伤害或事件。`Pause / Reset / IsFinished / Duration` 使用相同接口。

独立播放器使用 `Player:Update(dt)`；FSM 驱动时只使用 `Seek(record.elapsed)`，不可再对主动作调用 `Update`。代码反馈的 `Update(dt)` 返回短停后可用的时间，状态机与移动共用该余量。渲染只读取 `Sample`，不计算序列帧或反馈曲线。

`Sample` 不新建表：每个动画实例和 `Player` 各自复用一张结果表（`Player` 的 `feedback` 子表同样复用），返回值在同一实例下一次 `Sample` 前有效。每帧大量角色采样也不产生 GC 垃圾；需要跨帧保存时复制字段，不要持有返回表，也不要修改其中的 `source`（它是共享的动作定义）。对象池复用播放器时，先 `Player:Reset()`，再用 `HitFeedbackAnimation:Rebind(clock)` 把受击反馈接到新实体的时钟。

游戏绑定在 `game/animation/Bindings.lua`，枚举在 `AnimationId.lua`。枚举值沿用原状态字符串；统一动作数据仍来自 `game.EnemyAnimations`。`EnemyAnimator` 用弱引用缓存实体实例，序列帧时间从 FSM 恢复，代码反馈只保存原有 `flash / hitStop / hitImmune` 字段。类实例与函数不进入版本7存档。

缺失动作绑定基类，采样输出 `visible=false`。静态造型显式绑定一帧循环序列。受击始终绑定代码反馈类，旧受击视频即使保留制作记录也不参与播放。
