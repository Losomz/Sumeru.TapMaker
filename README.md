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

- 同步器随框架放在 `scripts/sumeru/` 里：双击 `同步框架.cmd`，询问是否先更新框架，然后把框架同步到当前项目，跑完停住看结果。同步器本身也是框架文件，每次同步自动更新。
- 框架仓库默认放在与游戏项目同级的 `Sumeru.TapMaker`，不存在时自动克隆。
- 新项目接入：把本仓库内容（除 `.git`）复制到项目的 `scripts/sumeru/`，双击一次 `同步框架.cmd`。
- Agent 免询问执行：`powershell -ExecutionPolicy Bypass -File .\scripts\sumeru\sync.ps1 -Update`（或 `-NoUpdate`）。
- 框架改动在本仓库提交、推送后，再到各项目双击同步，不要只改项目副本。
- `.meta` 含项目与作者信息，不入本仓库；同步后由各项目用 Maker MCP `generate_resource_meta` 为新文件生成。
- 业务代码通过 `require("sumeru.toolkit.<kit>")` 引用；框架代码不引用任何业务模块，UIKit 的宿主与项目控件通过 `UIKit:Configure` 注入（见 [UIKit 接入配置](toolkit/uikit/README.md#接入配置)）。
