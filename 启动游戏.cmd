@echo off
rem Start the game window via dev\sumeru\play.ps1; this console closes on success and stays open on error.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0dev\sumeru\play.ps1" %* || pause
