@echo off
:: Check for admin rights, re-launch elevated if needed
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)
cd /d "%~dp0"
start "" pythonw spotibridge.py
