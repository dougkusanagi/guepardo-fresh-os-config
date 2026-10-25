@echo off
rem Executa o modulo sem exigir que o usuario memorize opcoes do PowerShell.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0modules\jellyfin.ps1" %*
exit /b %errorlevel%
