# 资源分包下载 Kit

`require("sumeru.toolkit.loadkit")` 返回通用分包下载器。UrhoX 线上运行时脚本与配置启动前已就绪，图片、声音、字体按需下载（DWP）；本 Kit 在此之上按业务把资源分成包，决定什么时候下哪一包。

```lua
local LoadKit=require("sumeru.toolkit.loadkit")
local loads=LoadKit.new()
loads:Define("core",coreRefs)
loads:Define("level:1",level1Refs)
loads:Define("audio",audioRefs)

-- 首屏：确保必需包就绪，期间显示进度。
loads:Ensure({"core","level:1"},{
    onProgress=function(done,total) ShowProgress(done/total) end,
    onReady=function() EnterGame() end,
    onFail=function(failedCount) ShowRetry() end, -- 重试调用 loads:Retry()
})

-- 进游戏后后台预取，按顺序每次一个包。
loads:Prefetch({"level:2","audio","level:3"})
```

## 设计

- `Ensure` 只下载未就绪的包；全部已就绪时**同步**回调 `onReady`，调用方不会闪加载遮罩。
- 同一包被多次请求或已在后台预取时合并等待，不重复下载。
- `Prefetch` 在有 `Ensure` 等待时不启动新包，正在预取的单包继续完成；`Ensure` 结束后自动续上队列。
- 预取失败只记日志；之后用到时由 `Ensure` 再次下载，失败可 `Retry()` 重放最近一次失败请求。
- 包状态：`idle` / `loading` / `ready` / `failed`；`IsReady(name)` 查询。
- 本地预览资源已在磁盘上，下载回调立即完成，流程与线上一致。
