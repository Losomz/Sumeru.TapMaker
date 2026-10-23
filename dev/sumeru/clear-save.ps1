# 清除本游戏的本地存档：先关预览（避免退出时把存档写回去），再只删 savePrefix 开头的存档文件。
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "common.ps1")

$config = Get-LaunchConfig
$stopped = Stop-OwnPreview
if ($stopped) { Write-Host "已关闭预览 PID=$stopped" }

$saveRoot = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "temp\savedata"
if (-not (Test-Path -LiteralPath $saveRoot)) {
    Write-Host "没有找到存档目录：$saveRoot"
    return
}

$files = @(Get-ChildItem -LiteralPath $saveRoot -Recurse -File -Filter "$($config.savePrefix)*")
if ($files.Count -eq 0) {
    Write-Host "没有 $($config.savePrefix) 的存档：$saveRoot"
    return
}
foreach ($file in $files) {
    Remove-Item -LiteralPath $file.FullName -Force
    Write-Host "已删除 $($file.FullName)"
}
Write-Host "存档已清除，下次启动从新档开始。"
