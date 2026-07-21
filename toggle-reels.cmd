@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0reels.ps1" -Action toggle
timeout /t 1 >nul
