# Sumeru 框架

可复用能力和使用经验随 `sumeru/` 目录一起迁移。项目专用资源、业务规则和美术规范留在项目中。

## 工具包文档

- [UIKit：UI 绘制经验与九宫格接缝](toolkit/uikit/README.md)
- [AnimationKit](toolkit/animation/README.md)
- [FSM](toolkit/fsm/README.md)
- [FloatingTextKit](toolkit/floatingtext/README.md)
- [AudioKit](toolkit/audiokit/README.md)
- [SaveKit：按结构声明合并的存档读写](toolkit/savekit/README.md)
- [LoadKit：资源分包按需下载与后台预取](toolkit/loadkit/README.md)

## 接入游戏项目

本仓库是框架源码的唯一来源，各 TapTap Maker 游戏项目保存一份同步副本于 `scripts/sumeru/`（普通文件，不用 git submodule，构建不受影响）。

- 同步逻辑在本仓库根目录 `sync.ps1`，随框架一起更新；游戏项目只放启动脚本 `dev/sync-sumeru.ps1`（模板为根目录 `launcher.ps1`，同步时自动保持最新）。
- 新项目接入：把 `launcher.ps1` 复制为项目的 `dev/sync-sumeru.ps1`，运行一次即可（框架仓库默认放在与项目同级的 `Sumeru.TapMaker`，不存在时自动克隆）。
- 日常同步：`powershell -ExecutionPolicy Bypass -File .\dev\sync-sumeru.ps1`，启动时询问是否先更新框架；`-Update` 直接更新，`-NoUpdate` 跳过更新，供 Agent 无交互执行。
- 框架改动在本仓库提交、推送后，再到各项目运行启动脚本同步，不要只改项目副本。
- `.meta` 含项目与作者信息，不入本仓库；同步后由各项目用 Maker MCP `generate_resource_meta` 为新文件生成。
- 业务代码通过 `require("sumeru.toolkit.<kit>")` 引用。
- 已知耦合：`toolkit/uikit` 仍引用 `game.ui.ScreenHost` 与若干 `game.ui.*` 控件，新项目需提供同名模块或先解耦。
