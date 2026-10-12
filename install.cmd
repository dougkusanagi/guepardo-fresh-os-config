@echo off
rem Launcher Windows do instalador Go.
setlocal
pushd "%~dp0"
where go.exe >nul 2>&1
if errorlevel 1 (
    echo Go 1.22 ou superior nao foi encontrado. Use o launcher do OneDrive ou instale o Go.
    popd
    exit /b 1
)
go run ./cmd/guepardo %*
set "installerExitCode=%errorlevel%"
popd
exit /b %installerExitCode%
