@echo off
setlocal EnableExtensions DisableDelayedExpansion
rem CheckM2 1.0.2 on an already completed LorBin run; no LorBin training is started.
rem Example: run_checkm2.bat -RunDirectory "D:\project\article\LorBin\handreproduce\runs\NAME" -Threads 4
rem Default results: RUN_DIRECTORY\checkm2_reproduce\quality_report.tsv
where pwsh.exe >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    pwsh.exe -NoLogo -NoProfile -File "%~dp0run_checkm2.ps1" %*
) else (
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_checkm2.ps1" %*
)
exit /b %ERRORLEVEL%
