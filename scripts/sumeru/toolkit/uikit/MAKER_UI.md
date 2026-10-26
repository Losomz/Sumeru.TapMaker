# Maker UI 目录与迁移说明

## 后台扫描范围

Maker 控制台的 UI 编辑器递归扫描项目 **整个 `assets/` 目录**，将后缀为 `.ui.json` 的文件列为 UI 文档；`assets/ui/` 是本框架推荐的统一存放位置，不是后台唯一允许的子目录。

`scripts/` 和 `assets/` 是项目根目录下的并列目录。引擎把两者都作为资源根，不代表 Maker 编辑器也扫描两者：放在 `scripts/` 的 JSON 可以被游戏加载，但不会出现在后台的 UI 文档列表中。

目录里的 `.ui.json.meta` 是资源元数据，不是第二份 UI 文档。后台跳过隐藏项和符号链接，不要用目录链接代替正式迁移。

## 新项目推荐结构

```text
游戏项目/
├─ assets/
│  └─ ui/
│     ├─ panels/
│     │  └─ home/
│     │     ├─ home.ui.json
│     │     └─ home.ui.json.meta
│     └─ components/
│        └─ card/
│           ├─ card.ui.json
│           └─ card.ui.json.meta
└─ scripts/
   └─ ui/
      ├─ panels/home/home.lua
      └─ components/card/card.lua
```

- JSON 保存布局、层级、图片引用和稳定节点 ID；Lua 保存交互、状态、动画和动态列表逻辑。
- 游戏与编辑器使用同一份正式 JSON，不另存一套“后台专用副本”。编辑器保存的修改应能被游戏直接读取。
- 运行时资源路径从资源根的下一层开始。例如 JSON 引用 `ui/panels/home/home.ui.json`，图片引用 `image/button.png`，不写 `assets/` 前缀。
- 上述结构中，`panelRoot="ui/panels"` 对应 JSON 资源 `ui/panels/<key>/<key>.ui.json` 和 Lua 模块 `ui.panels.<key>.<key>`；组件也可用 `componentRoot="ui/components"` 同名推导。
- 显式注册 JSON 组件时分别写模板资源和 Lua 模块：

```lua
local Components=require("sumeru.toolkit.uikit.ComponentRegistry")
Components:RegisterTemplate("Card","ui/components/card/card.ui.json","ui.components.card.card")
```

## 旧项目迁移

先核对当前入口、注册配置、运行时模板引用和项目已有改动，再迁移；已有布局不重新生成。

1. 把正式 `.ui.json` 移到 `assets/ui/`，保持页面、组件和条目模板的目录层级。
2. 同时移动对应 `.meta`，保持 UUID 和文件内容；已有有效 UUID 不重新生成。确实新增或缺少元数据时，使用 Maker MCP `generate_resource_meta`，不手写 UUID。
3. 保留节点 ID、组件名、模板参数、显隐和布局值；Lua Controller 可以保留原位置。
4. 更新 UIKit 默认路径、显式 `template`、`RegisterTemplate`、动态 `CreateChild`、预加载清单及生成脚本。不能只改页面入口而漏掉条目、弹窗或宿主。
5. 移除旧位置的 JSON，确保每份布局只有一个来源；不要靠复制或链接让两边各维护一份。
6. 同步项目的文档和检查脚本，使它们扫描新目录并能定位原 Controller。

### JSON 与 Controller 的相对路径不同

当前框架的 `panelRoot` 同时参与 JSON 路径和 Lua 模块名推导，没有独立的 JSON 根配置项。比如旧 Controller 保留在 `scripts/game/ui/panels/`，JSON 迁到 `assets/ui/panels/`，仅把 `panelRoot` 改为 `ui/panels` 会让框架转而查找 `ui.panels.*` Controller。

普通页面可显式指定 `template` 和 `controller`；**MainShell、GameShell、Overlay 也必须一起处理**，它们通过 `PanelRegistry:Paths` 推导路径，不会自动采用业务页面的覆盖值。

需要保留旧 Lua 命名空间的项目，可在项目接入代码中使用以下过渡适配，框架副本保持不改：

```lua
local UIKit=require("sumeru.toolkit.uikit.UIKit")

-- JSON 从 assets/ui 读取，Controller 保留 scripts/game/ui 的命名空间。
local function panelPaths(registry,key)
 local module=registry.root:gsub("/", ".")
 return "ui/panels/"..key.."/"..key..".ui.json",module.."."..key.."."..key
end

UIKit:Configure({panelRoot="game/ui/panels",componentRoot="ui/components"})
UIKit.registry_.Paths=panelPaths
-- 在此之后注册业务页面；组件用 RegisterTemplate 显式绑定原 Lua 模块。
```

这是针对当前注册器的项目侧过渡适配，使用了 `registry_` 内部接口；同步框架后应复核。创建新的 UIKit 注册器时需重新安装该适配。新项目优先使用上方同相对路径结构，避免依赖内部接口。

## 核对后台与游戏

使用当前安装的 Maker CLI，始终带明确的游戏项目目录：

```text
taptap-maker ui list --target-dir <游戏项目绝对路径> --json
taptap-maker ui inspect --target-dir <游戏项目绝对路径> --file assets/ui/panels/home/home.ui.json --json
```

- `ui list` 应列出实际迁入的文件；打开后台 UI 编辑器后点击「刷新文件」。文件列表更新不需要远端构建或提交。
- 核对游戏所有 JSON 引用、Controller 模块、预加载资源和 UUID，不只确认文件能被 JSON 解析器读取。
- 按项目授权约定运行 Maker 随包 `lua-ui-to-json` 静态检查及项目自己的检查；报告实际错误、警告和未检查项。
- 需要验证游戏时使用该项目现有的本地预览入口；没有运行就明确标记未验证，不用编辑器截图代替游戏运行证据。

## 自定义控件与编辑器限制

“后台发现文件”“编辑器能完整预览”“游戏实际正确运行”是三个不同的核对结果。

- `FrameworkButton`、项目 Widget 和 JSON 组件依赖 Lua 注册；浏览器编辑器不执行游戏 Controller。保留真实类型，不为了消除提示而改成 `Panel`。
- Sumeru `Json` 适配器把 Widget 的 `component` 字段视为登记名，用于组件 Controller 生命周期；Maker 静态检查把它视为文件路径。因此登记名可能触发 `UI_COMPONENT_MISSING`，应核对 `RegisterTemplate` 的真实资源与模块，再单独处理编辑器兼容，不能直接断言运行文件丢失。
- 模板参数、运行时尺寸、初始隐藏和空动态容器都需要调用上下文。空容器不等于漏导出，不要强制显隐、固定尺寸或填入存档数据来制造完整画面。
- 检查通过不证明字体、布局、组件展开、图片解码或 Lua 绑定正确；运行时预览通过也不证明浏览器编辑器具备相同控件能力。

## 框架维护与同步

通用改动先在框架仓库提交并推送，再到游戏项目运行现有的 `dev/sumeru/sync.ps1` 同步。不要只改项目的 `scripts/sumeru/` 副本，否则后续镜像同步会覆盖该修改。

同步框架不会自动迁移各游戏的业务 UI 或改写它们的加载引用。每个旧项目都应按上方步骤单独迁移；本说明随 `scripts/sumeru/toolkit/uikit/` 一起同步，供其他项目复用。
