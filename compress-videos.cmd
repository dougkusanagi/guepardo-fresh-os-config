@echo off
rem Compacta videos para outra pasta sem alterar os originais (veja o README).
where uv >nul 2>nul
if %errorlevel%==0 (
  uv run --no-project --python 3.11 python "%~dp0scripts\compress-videos.py" %*
) else (
  python "%~dp0scripts\compress-videos.py" %*
)
exit /b %errorlevel%
