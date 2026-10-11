@echo off
rem Entrada Windows: menu e perfis do install.ps1, sem opcoes do PowerShell.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
exit /b %errorlevel%
