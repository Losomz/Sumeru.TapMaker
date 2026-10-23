@echo off
rem Close the preview started by play.ps1, then delete only this game's local save files.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0dev\sumeru\clear-save.ps1" %* & pause
