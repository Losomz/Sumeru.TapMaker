[CmdletBinding()]
param(
    # 框架仓库本地路径，默认与本项目同级的 Sumeru.TapMaker。
    [string]$Source = "",
    # 直接更新框架到最新，不询问。
    [switch]$Update,
    # 直接用本地框架同步，不更新、不询问。
    [switch]$NoUpdate
)

# Sumeru 框架启动脚本：由框架 launcher.ps1 维护，放在游戏项目 dev/ 下；同步逻辑在框架根目录 sync.ps1，随框架更新。
$ErrorActionPreference = "Stop"

$repoUrl = "https://github.com/Losomz/Sumeru.TapMaker.git"
$projectRoot = Split-Path -Parent $PSScriptRoot
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

& (Join-Path $Source "sync.ps1") -Project $projectRoot
