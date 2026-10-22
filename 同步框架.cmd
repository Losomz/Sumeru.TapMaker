@echo off
rem Sumeru framework sync: double-click to run. Kept on one line so cmd never re-reads this file after sync replaces it.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0sync.ps1" %* & pause & exit /b
