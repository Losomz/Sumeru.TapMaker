# 发布物料

Maker「管理发布」上传到 TapTap 的图片，以本目录的文件为准。规则与流程见 `dev/sumeru/publish/README.md`。

| 文件 | 本地路径字段 / 地址字段 | TapTap 要求 |
|---|---|---|
| `icon.png` | `icon` / `icon_url` | ≥512×512，1:1（建议 1024×1024） |
| `promo-banner.jpg` | `promotional_image` / `promotional_image_url` | ≥1920×1080，16:9，≤4MB |
| `promo-square.png` | `square_promotional_image` / `square_promotional_image_url` | ≥1440×1440，1:1，≤4MB |
| `cover-horizontal.png` | `cover_horizontal` / `cover_horizontal_url` | 参照 Maker 管理发布页给的尺寸 |
| `cover-vertical.png` | `cover_vertical` / `cover_vertical_url` | 参照 Maker 管理发布页给的尺寸 |
| `screenshot-1.png` … | `screenshots` / `screenshot_urls` | 实机截图，至少 3 张 |

`.project/project.json` 写法：

```json
"assets": {
  "icon": "docs/publish-materials/icon.png",
  "icon_url": "<同一张图上传 TapTap 后的地址>",
  "promotional_image": "docs/publish-materials/promo-banner.jpg",
  "promotional_image_url": "<同上>"
}
```

换图三步：
1. 覆盖本目录的同名文件；
2. 上传 TapTap 拿到地址，填进 `*_url`；
3. 运行 `dev/sumeru/publish-check.ps1` 检查，没有错误再推送。
