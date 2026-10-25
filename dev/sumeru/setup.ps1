# 项目初始化：补齐 dev/launch.json、构建忽略规则、换行规则、.gitignore 与 docs 下的发布模板。只补缺，不覆盖已有内容，可重复运行。
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

$utf8 = New-Object System.Text.UTF8Encoding($false)

# dev/launch.json：窗口尺寸与横竖屏按 Maker 的 screen_orientation 取默认值，之后由项目自己改。
$launch = Join-Path $ProjectRoot "dev\launch.json"
if (-not (Test-Path -LiteralPath $launch)) {
    $orientation = "portrait"
    $projectJson = Join-Path $ProjectRoot ".project\project.json"
    if (Test-Path -LiteralPath $projectJson) {
        $value = (Get-Content -LiteralPath $projectJson -Raw -Encoding UTF8 | ConvertFrom-Json).screen_orientation
        if ($value -eq "landscape") { $orientation = "landscape" }
    }
    $size = if ($orientation -eq "portrait") { @(480, 853) } else { @(853, 480) }
    $text = "{`n  `"width`": $($size[0]),`n  `"height`": $($size[1]),`n  `"orientation`": `"$orientation`",`n  `"savePrefix`": `"$(Split-Path -Leaf $ProjectRoot)`"`n}`n"
    [System.IO.File]::WriteAllText($launch, $text, $utf8)
    Write-Host "已生成 dev/launch.json（$orientation $($size[0])x$($size[1])），按需修改。"
}

# 构建忽略：框架文档不进包。settings.json 由 Maker 首次构建生成，没有时跳过。
$settings = Join-Path $ProjectRoot ".project\settings.json"
if (Test-Path -LiteralPath $settings) {
    $raw = [System.IO.File]::ReadAllText($settings)
    $json = $raw | ConvertFrom-Json
    $ignores = @($json.build.asset_ignores | Where-Object { $_ })
    $want = @("**/*.md", "**/*.ps1", "**/*.cmd")
    $lack = @($want | Where-Object { $ignores -notcontains $_ })
    if ($lack.Count -gt 0) {
        $list = "[" + ((@($ignores + $lack) | ForEach-Object { "`"$_`"" }) -join ", ") + "]"
        $pattern = '("asset_ignores"\s*:\s*)\[[^\]]*\]'
        if ($raw -match $pattern) {
            # 只替换这一个数组的文本，保留 Maker 生成文件的原有格式。
            $raw = [regex]::Replace($raw, $pattern, { param($m) $m.Groups[1].Value + $list }, 1)
        } else {
            if (-not $json.build) { $json | Add-Member -NotePropertyName build -NotePropertyValue ([pscustomobject]@{}) }
            $json.build | Add-Member -NotePropertyName asset_ignores -NotePropertyValue ([object[]]($ignores + $lack)) -Force
            $raw = ConvertTo-Json -InputObject $json -Depth 32
        }
        [System.IO.File]::WriteAllText($settings, $raw, $utf8)
        Write-Host ("已在 .project/settings.json 的 asset_ignores 加入：" + ($lack -join ", "))
    }
} else {
    Write-Host "还没有 .project/settings.json，首次 Maker 构建后再同步一次以补上构建忽略规则。"
}

# 广告配置检查：业务脚本用到激励视频，但本地 settings.json 没有 @runtime.ad 时，正式包没有广告位必然播放失败。
# get_ad_config 只写 Maker 远端工作区，这里只能提示，不能代为获取。
$scriptsDir = Join-Path $ProjectRoot "scripts"
if (Test-Path -LiteralPath $scriptsDir) {
    $frameworkDir = Join-Path $scriptsDir "sumeru"
    $usesAd = Get-ChildItem -LiteralPath $scriptsDir -Recurse -File -Filter *.lua |
        Where-Object { -not $_.FullName.StartsWith($frameworkDir, [System.StringComparison]::OrdinalIgnoreCase) } |
        Select-String -Pattern 'ShowRewardVideoAd|sumeru\.toolkit\.adkit' -List | Select-Object -First 1
    if ($usesAd) {
        $hasAd = $false
        if (Test-Path -LiteralPath $settings) {
            $runtime = ([System.IO.File]::ReadAllText($settings) | ConvertFrom-Json).'@runtime'
            $hasAd = $null -ne $runtime -and $null -ne $runtime.ad
        }
        if (-not $hasAd) {
            Write-Host ""
            Write-Host "[警告] 项目使用了激励视频广告，但 .project/settings.json 缺少 @runtime.ad：" -ForegroundColor Yellow
            Write-Host "  Maker 预览正常，正式版会提示广告播放失败。用 Maker MCP get_ad_config 获取配置，" -ForegroundColor Yellow
            Write-Host "  把返回的 ad 块写进本地 settings.json 的 @runtime 并提交。详见 scripts/sumeru/toolkit/adkit/README.md" -ForegroundColor Yellow
        }
    }
}

# 发布物料与更新日志模板：项目里没有对应目录时复制一份，已有则不动。规则见 dev/sumeru/publish/README.md。
$templates = Join-Path $PSScriptRoot "publish\templates"
foreach ($dir in @(Get-ChildItem -LiteralPath $templates -Directory -ErrorAction SilentlyContinue)) {
    $target = Join-Path $ProjectRoot ("docs\" + $dir.Name)
    if (-not (Test-Path -LiteralPath $target)) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
        Copy-Item -LiteralPath $dir.FullName -Destination $target -Recurse
        Write-Host "已生成 docs/$($dir.Name)/，用法见 dev/sumeru/publish/README.md"
    }
}

# 发布物料检查：本地路径还指向 Maker 生成的 game_material 文件时，出包会把旧图传到 TapTap，覆盖后台的修改。
$projectJson = Join-Path $ProjectRoot ".project\project.json"
if (Test-Path -LiteralPath $projectJson) {
    $assets = ([System.IO.File]::ReadAllText($projectJson) | ConvertFrom-Json).assets
    $stale = @("icon", "promotional_image", "square_promotional_image", "cover_horizontal", "cover_vertical") |
        Where-Object { $assets -and "$($assets.$_)" -like "*game_material/*" }
    if ($stale) {
        Write-Host ""
        Write-Host ("[提示] 发布物料仍指向 Maker 生成的 game_material 文件：" + ($stale -join ", ")) -ForegroundColor Yellow
        Write-Host "  从 Maker 出包会把这些图传到 TapTap，覆盖后台的修改。改用 docs/publish-materials/，" -ForegroundColor Yellow
        Write-Host "  并运行 dev/sumeru/publish-check.ps1 检查。详见 dev/sumeru/publish/README.md" -ForegroundColor Yellow
    }
}

# 追加缺少的行到文本文件，文件不存在则创建。
function Add-Lines([string]$path, [string[]]$lines) {
    $existing = @()
    if (Test-Path -LiteralPath $path) { $existing = @(Get-Content -LiteralPath $path -Encoding UTF8 | ForEach-Object { $_.Trim() }) }
    $lack = @($lines | Where-Object { $existing -notcontains $_ })
    if ($lack.Count -eq 0) { return }
    $prefix = ""
    if ((Test-Path -LiteralPath $path) -and (Get-Item -LiteralPath $path).Length -gt 0) {
        $raw = [System.IO.File]::ReadAllText($path)
        if (-not $raw.EndsWith("`n")) { $prefix = "`n" }
    }
    [System.IO.File]::AppendAllText($path, $prefix + ($lack -join "`n") + "`n", $utf8)
    Write-Host ("已在 " + (Split-Path -Leaf $path) + " 加入：" + ($lack -join ", "))
}

# 换行规则：cmd/ps1 必须 CRLF，否则 Windows 解析失败；sh 必须 LF。
Add-Lines (Join-Path $ProjectRoot ".gitattributes") @("*.cmd text eol=crlf", "*.ps1 text eol=crlf", "*.sh text eol=lf")
Add-Lines (Join-Path $ProjectRoot ".gitignore") @(".tmp/")
