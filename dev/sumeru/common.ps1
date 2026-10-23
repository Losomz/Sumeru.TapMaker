# dev/sumeru 工具共用：项目根、dev/launch.json 配置、运行时定位，以及只关闭本工具启动的预览窗口。
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$RuntimeRoot = Join-Path $env:USERPROFILE ".taptap-maker\runtime"
$PidFile = Join-Path $ProjectRoot ".tmp\local-preview.pid"

# 读取 dev/launch.json，缺失的字段用默认值：竖屏 480x853，存档前缀为项目文件夹名。
function Get-LaunchConfig {
    $config = [ordered]@{ width = 480; height = 853; orientation = "portrait"; savePrefix = (Split-Path -Leaf $ProjectRoot) }
    $path = Join-Path $ProjectRoot "dev\launch.json"
    if (Test-Path -LiteralPath $path) {
        $json = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($p in $json.PSObject.Properties) { $config[$p.Name] = $p.Value }
    }
    return $config
}

# 优先用 Maker 记录的当前运行时，找不到再退回最新的 runtime-* 目录。
function Get-RuntimeExe {
    $install = Join-Path $RuntimeRoot "installation.json"
    if (Test-Path -LiteralPath $install) {
        $exe = (Get-Content -LiteralPath $install -Raw | ConvertFrom-Json).executable
        if ($exe -and (Test-Path -LiteralPath $exe)) { return $exe }
    }
    $latest = Get-ChildItem -LiteralPath $RuntimeRoot -Directory -Filter "runtime-*" -ErrorAction SilentlyContinue |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "UrhoXRuntime.exe") } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($latest) { return Join-Path $latest.FullName "UrhoXRuntime.exe" }
    throw "未找到 TapTap Maker 本地运行时，请先在 Maker 里安装本地预览：$RuntimeRoot"
}

# 只关闭 pid 文件记录、且确实是 Maker 运行时的那个进程，绝不按进程名批量关闭（会误关其他游戏）。返回关掉的 PID，没有则 0。
function Stop-OwnPreview {
    if (-not (Test-Path -LiteralPath $PidFile)) { return 0 }
    $stopped = 0
    $previewPid = 0
    if ([int]::TryParse((Get-Content -LiteralPath $PidFile -Raw).Trim(), [ref]$previewPid)) {
        $process = Get-Process -Id $previewPid -ErrorAction SilentlyContinue
        if ($process -and $process.ProcessName -eq "UrhoXRuntime") {
            $path = $null
            try { $path = $process.Path } catch {}
            if ($path -and $path.StartsWith($RuntimeRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                Stop-Process -Id $previewPid -Force
                $process.WaitForExit()
                $stopped = $previewPid
            }
        }
    }
    Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
    return $stopped
}
