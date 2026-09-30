@echo off
setlocal EnableExtensions DisableDelayedExpansion

rem Double-click to start the full 300-epoch single-sample run in Docker detached mode.
rem --check performs a safe preflight; --status and --logs inspect the latest run.
if /I "%~1"=="--check" goto check
if /I "%~1"=="--status" goto status
if /I "%~1"=="--logs" goto logs
if not "%~1"=="" goto usage
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_lorbin_detached.ps1"
exit /b %ERRORLEVEL%

:check
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_lorbin_detached.ps1" -Check
exit /b %ERRORLEVEL%

:status
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_lorbin_detached.ps1" -Status
exit /b %ERRORLEVEL%

:logs
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_lorbin_detached.ps1" -Logs
exit /b %ERRORLEVEL%

:usage
echo Unknown option: %~1
echo Usage: %~nx0 [--check^|--status^|--logs]
exit /b 2
