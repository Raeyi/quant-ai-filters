@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0start_web_ui.ps1"
endlocal
