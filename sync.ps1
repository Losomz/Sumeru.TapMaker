[CmdletBinding()]
param(
    # 目标游戏项目根目录；框架同步到其 scripts/sumeru/。
    [Parameter(Mandatory = $true)][string]$Project
)

$ErrorActionPreference = "Stop"

$Source = $PSScriptRoot
$target = Join-Path $Project "scripts\sumeru"

# 返回需要同步的框架文件相对路径：只含 framework/、toolkit/ 与根 README.md，不含 .meta。
function Get-SyncFiles([string]$root) {
    $prefix = (Resolve-Path -LiteralPath $root).Path.TrimEnd('\') + '\'
    Get-ChildItem -LiteralPath $root -Recurse -File |
        Where-Object { $_.Extension -ne '.meta' } |
        ForEach-Object { $_.FullName.Substring($prefix.Length) } |
        Where-Object { $_ -match '^(framework|toolkit)\\' -or $_ -eq 'README.md' }
}

# 按字节比较两个文件内容是否一致（Windows PowerShell 5 不保证有 Get-FileHash）。
function Test-SameContent([string]$a, [string]$b) {
    $x = [System.IO.File]::ReadAllBytes($a)
    $y = [System.IO.File]::ReadAllBytes($b)
    return [System.Linq.Enumerable]::SequenceEqual($x, $y)
}

New-Item -ItemType Directory -Force -Path $target | Out-Null
$sourceFiles = @(Get-SyncFiles $Source)
$sourceSet = @{}
foreach ($rel in $sourceFiles) { $sourceSet[$rel.ToLowerInvariant()] = $true }

$added = @(); $updated = @(); $removed = @()

# 新增或内容变化的文件覆盖到项目副本；已有 .meta 保持不动。
foreach ($rel in $sourceFiles) {
    $from = Join-Path $Source $rel
    $to = Join-Path $target $rel
    if (-not (Test-Path -LiteralPath $to)) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $to) | Out-Null
        Copy-Item -LiteralPath $from -Destination $to
        $added += $rel
    } elseif (-not (Test-SameContent $from $to)) {
        Copy-Item -LiteralPath $from -Destination $to -Force
        $updated += $rel
    }
}

# 框架已删除的文件连同 .meta 一起从项目副本移除。
foreach ($rel in @(Get-SyncFiles $target)) {
    if (-not $sourceSet.ContainsKey($rel.ToLowerInvariant())) {
        $path = Join-Path $target $rel
        Remove-Item -LiteralPath $path -Force
        Remove-Item -LiteralPath ($path + ".meta") -Force -ErrorAction SilentlyContinue
        $removed += $rel
    }
}

# 清理失去源文件的孤立 .meta 与空目录。
Get-ChildItem -LiteralPath $target -Recurse -File -Filter *.meta |
    Where-Object { -not (Test-Path -LiteralPath ($_.FullName.Substring(0, $_.FullName.Length - 5))) } |
    Remove-Item -Force
Get-ChildItem -LiteralPath $target -Recurse -Directory |
    Sort-Object { $_.FullName.Length } -Descending |
    Where-Object { -not (Get-ChildItem -LiteralPath $_.FullName -Force) } |
    Remove-Item -Force

# 项目里的启动脚本与框架模板不一致时替换，下次启动生效。
$launcherTemplate = Join-Path $Source "launcher.ps1"
$launcher = Join-Path $Project "dev\sync-sumeru.ps1"
if (-not (Test-Path -LiteralPath $launcher) -or -not (Test-SameContent $launcherTemplate $launcher)) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $launcher) | Out-Null
    Copy-Item -LiteralPath $launcherTemplate -Destination $launcher -Force
    Write-Host "启动脚本 dev/sync-sumeru.ps1 已更新为框架版本，下次运行生效"
}

$commit = (git -C $Source log -1 --format="%h %s").Trim()
Write-Host "框架版本：$commit"
Write-Host ("新增 {0}，更新 {1}，删除 {2}" -f $added.Count, $updated.Count, $removed.Count)
$added + $updated + $removed | ForEach-Object { Write-Host "  $_" }

# 列出缺少 .meta 的脚本和资源（README 等文档不需要），交由 Maker MCP generate_resource_meta 生成。
$missing = @(Get-SyncFiles $target | Where-Object {
    $_ -notmatch '\.md$' -and -not (Test-Path -LiteralPath ((Join-Path $target $_) + ".meta"))
})
if ($missing.Count -gt 0) {
    Write-Host "以下文件缺少 .meta，请用 Maker MCP generate_resource_meta 生成："
    $missing | ForEach-Object { Write-Host ("  scripts/sumeru/" + ($_ -replace '\\', '/')) }
}
