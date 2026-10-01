@echo off
setlocal EnableExtensions DisableDelayedExpansion
title LorBin - CheckM2
rem CheckM2 1.0.2 on an already completed LorBin run; no LorBin training is started.
rem This command RUNS CheckM2 in Docker. To count an existing TSV only, use summarize_checkm2.bat.
rem No arguments: scan runs and select the latest SUCCEEDED LorBin run.
rem Run order: timestamp in run name; fallback: run folder modification time.
rem Running/failed runs are skipped. -RunDirectory overrides auto-selection.
rem For saved bins with an unavailable training exit code, explicitly use -RunDirectory and -AllowExistingBins.
rem Example: run_checkm2.bat -RunDirectory "D:\project\article\LorBin\handreproduce\runs\NAME" -Threads 4
rem Default result root: RUN_DIRECTORY\checkm2\
rem origin\ contains raw quality_report.tsv, CheckM2 output files, and Docker logs.
rem summary\ contains quality_summary.txt, bins_quality.tsv, provenance.json, and bins_manifest.tsv.
rem Read summary\quality_summary.txt first: Chinese HQ/MQ/Other counts and explanations.
rem Open summary\bins_quality.tsv in Excel (Tab delimiter) for each bin's HQ/MQ group.
rem summary\provenance.json records versions, inputs, and origin/summary paths.
rem Existing output folders are NOT overwritten. Repeat with -OutputName checkm2_2.
rem Double-click (no arguments): keep the window open after success or failure.
rem With arguments: return the exit code without pausing, for command-line automation.
echo [START] CheckM2 quality prediction. No LorBin training will be started.
echo Script: "%~dp0run_checkm2.ps1"
echo To count an existing report only, use summarize_checkm2.bat.
echo.
if not exist "%~dp0run_checkm2.ps1" (
    echo [ERROR] Missing run_checkm2.ps1. Keep the BAT and PS1 in the same folder.
    set "checkm2Exit=2"
    goto finish
)
where pwsh.exe >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_checkm2.ps1" %*
) else (
    "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_checkm2.ps1" %*
)
set "checkm2Exit=%ERRORLEVEL%"
:finish
echo.
if "%checkm2Exit%"=="0" (
    echo [SUCCESS] CheckM2 and the summary completed. Result paths are printed above.
) else (
    echo [ERROR] CheckM2 stopped. Exit code: %checkm2Exit%
    echo Read the error above. Docker Desktop must show its Linux engine running.
)
if "%~1"=="" pause
exit /b %checkm2Exit%
