﻿[CmdletBinding()]
param(
    # 框架仓库本地路径，默认与游戏项目同级的 Sumeru.TapMaker。
    [string]$Source = "",
    # 直接更新框架到最新，不询问。
    [switch]$Update,
    # 直接用本地框架同步，不更新、不询问。
    [switch]$NoUpdate
)

# Sumeru 框架同步器：随框架放在游戏项目 scripts/sumeru/ 下，双击同目录的「同步框架.cmd」运行，同步时连同自身一起更新。
$ErrorActionPreference = "Stop"

$repoUrl = "https://github.com/Losomz/Sumeru.TapMaker.git"
$target = $PSScriptRoot

if (Test-Path -LiteralPath (Join-Path $target ".git")) {
    Write-Host "这里是框架仓库本身，请到游戏项目的 scripts/sumeru/ 里运行同步。"
    return
}
if ((Split-Path -Leaf $target) -ne "sumeru" -or (Split-Path -Leaf (Split-Path -Parent $target)) -ne "scripts") {
    throw "同步器必须位于游戏项目的 scripts/sumeru/ 目录：$target"
}
$projectRoot = Split-Path -Parent (Split-Path -Parent $target)
if (-not $Source) { $Source = Join-Path (Split-Path -Parent $projectRoot) "Sumeru.TapMaker" }

# 框架仓库不存在时克隆；存在时按参数或询问决定是否快进拉取，避免覆盖本地未推送的框架改动。
if (-not (Test-Path -LiteralPath (Join-Path $Source ".git"))) {
    Write-Host "克隆框架仓库到 $Source"
    git clone $repoUrl $Source
    if ($LASTEXITCODE -ne 0) { throw "克隆框架仓库失败" }
} else {
    $pull = $Update
    if (-not $Update -and -not $NoUpdate) {
        $answer = Read-Host "是否先更新框架到最新？[Y/n]"
        $pull = $answer -notmatch '^[nN]'
    }
    if ($pull) {
        git -C $Source pull --ff-only
        if ($LASTEXITCODE -ne 0) { throw "更新框架仓库失败" }
    }
}

# 返回目录下需要同步的文件相对路径，不含 .git、.gitignore、.gitattributes 和 .meta。
function Get-SyncFiles([string]$root) {
    $prefix = (Resolve-Path -LiteralPath $root).Path.TrimEnd('\') + '\'
    Get-ChildItem -LiteralPath $root -Recurse -File |
        Where-Object { $_.FullName -notmatch '\\\.git\\' -and $_.Name -notin @('.gitignore', '.gitattributes') -and $_.Extension -ne '.meta' } |
        ForEach-Object { $_.FullName.Substring($prefix.Length) }
}

# 按字节比较两个文件内容是否一致（Windows PowerShell 5 不保证有 Get-FileHash）。
function Test-SameContent([string]$a, [string]$b) {
    $x = [System.IO.File]::ReadAllBytes($a)
    $y = [System.IO.File]::ReadAllBytes($b)
    return [System.Linq.Enumerable]::SequenceEqual($x, $y)
}

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

$commit = (git -C $Source log -1 --format="%h %s").Trim()
Write-Host "框架版本：$commit"
Write-Host ("新增 {0}，更新 {1}，删除 {2}" -f $added.Count, $updated.Count, $removed.Count)
$added + $updated + $removed | ForEach-Object { Write-Host "  $_" }

# 列出缺少 .meta 的脚本和资源（文档与同步器不需要），交由 Maker MCP generate_resource_meta 生成。
$missing = @(Get-SyncFiles $target | Where-Object {
    $_ -notmatch '\.(md|ps1|cmd)$' -and -not (Test-Path -LiteralPath ((Join-Path $target $_) + ".meta"))
})
if ($missing.Count -gt 0) {
    Write-Host "以下文件缺少 .meta，请用 Maker MCP generate_resource_meta 生成："
    $missing | ForEach-Object { Write-Host ("  scripts/sumeru/" + ($_ -replace '\\', '/')) }
}
