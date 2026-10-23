@echo off
rem Sumeru template sync: double-click to run. Kept on one line so cmd never re-reads this file after sync replaces it.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0dev\sumeru\sync.ps1" %* & pause & exit /b
