@echo off
rem Launcher do instalador Windows (PowerShell + Winget): .\install.cmd -Profiles cli,dev -Plan
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
exit /b %errorlevel%
