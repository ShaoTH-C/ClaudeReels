@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0reels.ps1" -Action site
echo.
pause
