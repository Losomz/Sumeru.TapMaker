@echo off
rem Close only the game window started by play.ps1 (tracked by .tmp\local-preview.pid).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0dev\sumeru\stop.ps1" %*
