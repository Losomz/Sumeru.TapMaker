# 通用音频 Kit

`require("sumeru.toolkit.audiokit")` 返回通用音频管理器，负责缓存 `Sound`、复用固定音效池和切换循环 BGM。

```lua
local AudioKit=require("sumeru.toolkit.audiokit")
local audio=AudioKit.new({
    music=tracks,
    sounds=effects,
    poolSize=12,
    musicGain=.28,
})

audio:SetSettings({music=true,sfx=true})
audio:PlayEffect("shot")
audio:SwitchBGM("battle")
```

## 设计

- `Sound` 按路径缓存，只加载一次。
- 音效播放源在初始化时一次性创建，默认 12 路，播放时循环复用。
- 音效池满时按优先级回收槽位；Boss、爆炸和警报优先于普通攻击音效。
- BGM 使用独立 `SoundSource`，不会占用音效池。
- `IsEffectPlaying(name)` 查询指定事件音效是否仍在播放，`StopEffect(name)` 只停止该事件；业务可据此等待一次性提示结束或在离开页面时收尾。
- `Track` 和 `Effect` 是兼容入口，分别等价于 `SwitchBGM` 和 `PlayEffect`。
- 复用播放源时显式传入 `frequency=0`，避免上一次播放的频率影响下一条音效。
