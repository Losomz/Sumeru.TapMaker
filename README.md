# Sumeru TapMaker 项目模板

TapTap Maker 游戏的起手模板：sumeru 框架 + 本地一键工具。仓库根目录就是游戏项目根目录的样子，复制进新项目即可用。

```
启动游戏.cmd / 关闭游戏.cmd / 清除存档.cmd / 同步框架.cmd   根目录一键脚本
scripts/sumeru/                            框架（UIKit、SaveKit、LoadKit、FSM、Animation……），见 scripts/sumeru/README.md
dev/sumeru/                                本地工具（启动、关闭、清存档、截图自检、同步、初始化），见 dev/sumeru/README.md
```

## 新项目接入
1. 用 Maker 创建并绑定项目（`taptap-maker init`），得到带 `.project/` 的项目目录。
2. 二选一：
   - 在本仓库运行 `powershell -ExecutionPolicy Bypass -File .\dev\sumeru\sync.ps1 -Project <项目根目录> -NoUpdate`；
   - 或者把本仓库内容（除 `.git`、`README.md`）复制到项目根目录，再双击项目里的 `同步框架.cmd`。
3. 同步会自动运行 `dev/sumeru/setup.ps1`，补齐：
   - `dev/launch.json`：窗口尺寸、横竖屏、存档前缀；
   - `.project/settings.json` 的构建忽略；
   - `.gitattributes` 换行规则、`.gitignore` 的 `.tmp/`。
4. 按同步结果的提示，用 Maker MCP `generate_resource_meta` 给 `scripts/sumeru/` 下缺 `.meta` 的文件生成 `.meta`。
5. 写好 `scripts/main.lua` 后，双击 `启动游戏.cmd`。

## 维护
- 框架和工具只在本仓库改，提交推送后到各项目双击 `同步框架.cmd`；不要只改项目里的副本。
- 同步时 `scripts/sumeru/`、`dev/sumeru/` 整目录镜像（本仓库删掉的文件，项目里也会删）；根目录 `.cmd` 只覆盖不删；项目自己的 `dev/launch.json` 不动。
- 老项目（同步器还在 `scripts/sumeru/sync.ps1` 的旧结构）不要再双击旧的 `scripts/sumeru/同步框架.cmd`，它会把新结构整个复制进 `scripts/sumeru/`。在本仓库用 `-Project` 迁移一次即可。
- `.meta` 含项目与作者信息，不入本仓库。
