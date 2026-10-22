@echo off
rem Sumeru framework launcher: double-click to sync; extra args are passed through, e.g. -Update / -NoUpdate.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0sync-sumeru.ps1" %*
pause
