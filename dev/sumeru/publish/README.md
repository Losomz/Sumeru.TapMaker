# 发布物料：Maker 与 TapTap 保持一致

TapTap 商店页的图标、宣传图、封面、截图、简介，最终都由 Maker「管理发布」出包时上传。下面是踩过坑后确认的规则。

## 原理：出包上传的是「本地路径」，不是网页上显示的图

`.project/project.json` 的 `assets` 里，每项物料有两个字段：

| 字段 | 作用 |
|---|---|
| 本地路径：`icon`、`promotional_image`、`square_promotional_image`、`cover_horizontal`、`cover_vertical`、`screenshots` | **出包时实际上传到 TapTap 的文件** |
| 地址：`icon_url`、`promotional_image_url`、`square_promotional_image_url`、`cover_*_url`、`screenshot_urls` | 只给 Maker 管理发布页显示用 |

两者不是同一张图时，网页上看着是对的，出包后 TapTap 却变成了路径指向的那张（通常是 Maker 最早生成的 AI 图）。在 TapTap 后台单独改过的物料，也会在下一次出包时被顶回去。

## 规则

1. **图片统一放在 `docs/publish-materials/`**，使用固定的英文文件名，本地路径都指向这里。这个目录不在资源根下，不会打进游戏包。
2. **同一张图两处一起改**：先覆盖本地文件，再把同一张图上传到 TapTap（`taptap-cli upload <文件> --dev-id <D> --app-id <A> --yes`），用返回的 `url` 更新对应的 `*_url`。
3. **本地路径不能删**：删掉 `icon`，管理发布会报「assets 缺少 icon 字段」，无法上传。
4. **不要把自己的图放进 `_uploads/`**：Maker 同步时会删掉它不认识的文件（只保留在 Maker 网页上传过的），删掉后路径会指向不存在的文件。
5. **`game_material/` 不能提交**：Maker 远端会拒绝推送。它下面的文件只在 Maker 服务器上，本地没法核对。
6. **截图用实机截图**：可以在 Maker 网页上传（会存进 `_uploads/` 并保留），也可以放进 `docs/publish-materials/`。不要用 AI 生成的截图。
7. **不要只在 TapTap 后台改物料**：要改就先改项目，再从 Maker 出包；后台只用来核对，或者处理 Maker 管不到的项（宣传片、实机录屏）。
8. **版本号不用手动改**：Maker 每次同步都会把 `version` 自动加 1。
9. **推送前先合并远端**：在 Maker 网页改过简介等文字后，远端会多出同步提交，本地要先拉取合并再推送。

## 出包流程

1. 改好 `docs/publish-materials/` 和 `project.json`，运行检查：
   ```
   powershell -ExecutionPolicy Bypass -File .\dev\sumeru\publish-check.ps1
   ```
   没有错误后，推送到 Maker（Maker 构建）。
2. 刷新 Maker 管理发布页，逐项核对显示是否正确。
3. 在管理发布页出包。
4. 出包后核对 TapTap 草稿：
   ```
   powershell -ExecutionPolicy Bypass -File .\dev\sumeru\publish-check.ps1 -Remote
   ```
   图标、宣传图、1:1 宣传图、简介、类型都应与 `project.json` 一致；截图需要人工确认是实机截图。
5. 不一致时回到第 1 步改项目，不要只在 TapTap 后台改。
6. 提审前运行一次 `taptap-cli app precheck-app-review --dev-id <D> --app-id <A> --data '{}'`。

## 检查脚本会拦下的问题

- `icon` 为空（出包会失败）。
- 路径指向 `game_material/`（多半是旧 AI 图，出包会覆盖 TapTap 后台的修改）。
- 路径指向自己放进 `_uploads/` 的文件（会被 Maker 删掉）。
- 文件不存在，或尺寸、比例、大小不符合 TapTap 要求：
  - 图标至少 512×512，1:1；
  - 宣传图至少 1920×1080，16:9，不超过 4MB；
  - 1:1 宣传图至少 1440×1440，不超过 4MB；
  - 截图至少 3 张。
- `*_url` 打不开，或者与本地文件尺寸不同（网页显示的图和实际上传的图不是同一张）。
- `-Remote`：TapTap 草稿的图标、宣传图、1:1 宣传图、标题、简介、类型与 `project.json` 不一致。

## 模板

首次同步时，`setup.ps1` 会在项目里补齐下面两个目录（已存在则不动）：

- `docs/publish-materials/`：发布物料目录，含文件名与字段对照表。
- `docs/更新日志/`：论坛更新公告，按版本分目录，含写作模板。
