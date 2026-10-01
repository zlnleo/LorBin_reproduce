@echo off
setlocal EnableExtensions DisableDelayedExpansion
rem Read an EXISTING CheckM2 TSV only. No Docker, CheckM2, or training is started.
rem No arguments: scan runs and select the latest SUCCEEDED run that already has a CheckM2 report.
rem Run order: timestamp in run name; fallback: run folder modification time.
rem Same run with multiple reports: select newest report modification time; print the selected path.
rem Raw input: RUN\OUTPUT\origin\quality_report.tsv; legacy RUN\OUTPUT\quality_report.tsv also works.
rem Running/failed runs and runs without reports are skipped. -ReportPath overrides auto-selection.
rem If checkm2.log exists beside a report, automatic selection requires its success message.
rem Example: summarize_checkm2.bat -ReportPath "D:\results\quality_report.tsv"
rem Optional: add -OutputDirectory "D:\results\summary_2" to keep an earlier summary.
rem Reports under project runs: default output is RUN\checkm2\summary\, including legacy report folders.
rem External reports: summary\ beside origin\, otherwise report folder\summary\.
rem Explicit -OutputDirectory is used as-is, without adding another summary folder.
rem Outputs: summary\quality_summary.txt (Chinese counts/help), summary\bins_quality.tsv (HQ/MQ per bin).
rem Repeated runs replace only these derived files; the raw input TSV is unchanged.
rem Default summary with provenance from a different report is protected; choose a new -OutputDirectory.
rem HQ: completeness >=90 and contamination <=5. MQ: completeness >=50 and contamination <10, excluding HQ.
rem These are CheckM2 proxies, not full MIMAG HQ certification.
where pwsh.exe >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    pwsh.exe -NoLogo -NoProfile -File "%~dp0summarize_checkm2.ps1" %*
) else (
    powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0summarize_checkm2.ps1" %*
)
set "summaryExit=%ERRORLEVEL%"
rem Keep the no-argument window open so a beginner can read the result or error.
if "%~1"=="" pause
exit /b %summaryExit%
