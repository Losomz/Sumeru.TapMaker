# AdKit：激励视频

`require("sumeru.toolkit.adkit")` 返回激励视频适配层，统一 `sdk:ShowRewardVideoAd` 的忙状态、同步拒绝、重复回调与失败兜底。

```lua
local AdKit=require("sumeru.toolkit.adkit")
local ad=AdKit.new({sdk=sdk,simulate=Platform.IsDesktopPlatform()})

if ad:CanRequest() then
    ad:ShowRewardVideo(function(result)
        if result.success then GrantReward() else ShowNotice("广告播放失败，请稍后重试") end
    end)
end
```

- 只有 `result.success==true` 才发奖；`"embed manual close"`（提前关闭）也是失败。
- 每次请求只回调一次；播放期间 `IsBusy()` 为真，重复点击直接返回 `false`。
- 失败时日志会打印 `[AdKit] 广告未完成 msg=...`，这是宿主/SDK 的原始结果，排查先看这一行。
- `simulate=true`（桌面本地开发）不调用宿主，直接按完整观看回调，只用来走通奖励链路。

## 广告位配置（上线前必查）

广告位由宿主从项目 `.project/settings.json` 的 `@runtime.ad` 读取，Lua 不写也不硬编码任何广告位 ID。

1. 用 Maker MCP `get_ad_config` 同步配置，确认 `ad.status == 1`。
2. **本地开发时**，`get_ad_config` 只把结果写进 Maker 远端工作区，不会写本地文件；而正式包从本地仓库构建，所以必须把返回的 `ad` 块原样写进本地 `.project/settings.json` 的 `@runtime` 下，并随代码一起提交：

   ```json
   "@runtime": {
       "ad": { "status": 1, "ad_spaces": [ ... ], "top_on_placements": [ ... ] }
   }
   ```

   `ad_spaces`、`top_on_placements` 照抄 `get_ad_config` 的返回值，不要自己编，也不要从别的项目复制。
3. 缺 `@runtime.ad` 时 Maker 预览仍然正常（预览走内置 FakeAd，不需要广告位），但**正式版必然提示播放失败**。所以预览和桌面 simulate 都不能证明正式广告可用，发版后要真机验证。
4. 广告开通状态或广告位变化后，重新 `get_ad_config` 并更新本地 `@runtime.ad`。

`dev/sumeru/setup.ps1`（每次同步框架时运行）会检查：项目脚本用到广告而 `settings.json` 缺 `@runtime.ad` 时给出警告。
