# 关闭本工具启动的游戏窗口；其他 UrhoXRuntime 进程不受影响。
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

$stopped = Stop-OwnPreview
if ($stopped) { Write-Host "已关闭预览 PID=$stopped" } else { Write-Host "没有由启动工具打开的预览窗口。" }
