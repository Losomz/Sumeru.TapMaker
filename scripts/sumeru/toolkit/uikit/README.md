# UIKit

入口为 `require("sumeru.toolkit.uikit.UIKit")`，负责 JSON 面板、宿主和组件生命周期。以下经验属于 UrhoX UI / NanoVG 绘制层，可随框架迁移到其他项目；不是对引擎参考库的修改。

## 接入配置

框架不引用任何业务模块。项目在注册面板前调用一次 `Configure`，把宿主判定、路径约定和项目控件注入进来：

```lua
local UIKit=require("sumeru.toolkit.uikit.UIKit")
local Components=require("sumeru.toolkit.uikit.ComponentRegistry")

UIKit:Configure({
 host=function(app) return app.inGame and "game" or "main" end, -- 当前业务宿主 Shell 名
 allows=function(def,app) return true end,                      -- 面板在当前阶段是否允许出现
 panelRoot="ui/panels",          -- 面板与 Shell：<root>/<key>/<key>.ui.json，控制器 ui.panels.<key>.<key>
 componentRoot="ui/components",  -- 未登记组件按 <root>/<slug>/<slug>.ui.json 查找
 shellComponents={game={"FrameworkButton","MyButton"}},           -- 各 Shell 预加载的组件
})
-- 项目自己的控件：Lua Widget 用 RegisterWidget，JSON 组件用 RegisterTemplate（均为首次使用时才加载）。
Components:RegisterWidget("MyButton",function() return require("ui.MyButton") end)
Components:RegisterTemplate("Card","ui/components/card/card.ui.json","ui.components.card.card")

UIKit:RegisterPanel("home",{shell="main",layer=UIKit.Layers.PhasePage})
UIKit:Attach(app,metrics)
```

| 字段 | 默认 | 说明 |
|---|---|---|
| `host(app)` | 始终 `"main"` | 返回当前宿主 Shell 名，变化时卸载旧 Shell 与其页面 |
| `allows(def,app)` | 始终允许 | 面板在当前阶段是否允许打开、显示和保留缓存 |
| `panelRoot` | `ui/panels` | 未显式写 `template`/`controller` 的面板和 Shell 按此推导路径 |
| `componentRoot` | 不设 | 不设时未登记组件直接报错 |
| `shellComponents` | `{}` | 按 Shell 名列出预加载组件 |

- 框架内置控件只有 `FrameworkButton`、`FrameworkToggle`、`FrameworkScrollView`。
- `Configure` 必须在 `RegisterPanel` 之前调用；配置在 `Destroy` 后保留。
- App 约定：`app.dirty` 为真时下一帧刷新全部可见页面；`metrics(app)` 返回 `w,h,vw,vh,safe{left,right},top,map,capsule,background`。

## 九宫格内部出现细线

### 现象和原因

图片本身没有线，拉伸后沿切片边界出现极细、断续的线，颜色可能随背后的场景变化。

当前官方 `Widget:RenderSlicedImage` 分别用九个矩形绘制各块图片。开启几何边缘抗锯齿时，每块的边缘都可能形成半透明过渡；内部接缝两侧的覆盖不足，便会透出后面的画面。缩放、小数坐标可能影响它的明显程度，但不能仅凭这些现象断言原因。

2026-10-18 的 360×640 本地实机对照中，同一炮台面板、同一图片、同一布局下：

- 官方默认绘制可复现右侧切片接缝。
- 仍调用官方九宫格，仅关闭该次绘制的几何边缘抗锯齿后，接缝消失；对应空白区域的像素恢复为底板纯色。
- 整图绘制也没有该接缝，但会改变边角拉伸效果，因此不作为九宫格的默认替代。

这个结论针对已复现的内部接缝，不代表所有细线都来自九宫格，也不足以认定所有引擎版本都有同样问题。

### 默认处理：全局开启，拼接局部关闭

保留官方切片算法，在目标控件实例上包装绘制方法：

```lua
local Panel=require("urhox-libs/UI/Widgets/Panel")

-- 仅关闭切片接合边的抗锯齿，结束后恢复调用前的状态。
local function renderJoinedSlices(widget,nvg,...)
 nvgSave(nvg)
 nvgShapeAntiAlias(nvg,0)
 Panel.RenderSlicedImage(widget,nvg,...)
 nvgRestore(nvg)
end

-- sheet 为 JSON 创建的目标 Panel 实例。
sheet.RenderSlicedImage=renderJoinedSlices
sheet:SetProp("backgroundFit","sliced")
sheet:SetProp("backgroundSlice",{20,20,20,20}) -- 上、右、下、左；按素材填写。
```

不要改只读的 `urhox-libs/` 参考副本，运行时可能加载内置的另一份。也不要为了一个接缝全局替换官方组件方法。

`nvgSave` / `nvgRestore` 必须成对使用；不要在结束时直接写 `nvgShapeAntiAlias(nvg,1)`，因为调用前的状态未必是开启。该开关控制几何路径边缘，不是文字抗锯齿、纹理过滤或引擎 MSAA 的总开关。局部关闭也可能使贴图外围的几何边缘更硬，应检查实际尺寸下的外轮廓。

全局 UI 默认保持抗锯齿，避免圆角、斜线和矢量图形变得生硬。若做全局对照，必须在每帧 `nvgBeginFrame` 之后设置；只在初始化时设置会被新帧重置。对照结束后移除临时覆盖。

### 分段场景背景与九宫格分开处理

同一背景分成多段、由多个 `overflow="hidden"` 容器裁剪时，裁剪边缘或各段布局取整也可能造成接缝。这不是官方九宫格。仅关闭图片路径的抗锯齿不一定能消除裁剪边缘。

需要保持分区伸缩时，可在单一背景控件内按共享边界连续绘制各段纹理，局部关闭几何边缘抗锯齿，并保留原有源图坐标、分区比例和整体父级裁剪。不要通过整图任意拉伸掩盖问题。这个方案仍需单独实机确认，不能借用九宫格的验证结论。

### 排查顺序

1. 检查原图、实际切片参数和当前运行时的绘制实现；区分素材线条、路径接缝和裁剪接缝。
2. 确认当前窗口确实加载了修改后的代码。预览工具报告的会话可能与项目独立启动脚本的进程不同，应核对实际进程和日志。
3. 保持图片和布局一致，对照默认绘制、局部关闭抗锯齿、整图绘制；读取引擎截图，必要时比较接缝像素。静态图片拼接不能证明运行时已经修复。
4. 保留验证有效的最小修复，恢复全局绘制状态，按项目约定清理临时测试产物。没有画面证据时明确标记尚未确认。
