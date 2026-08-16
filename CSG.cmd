@echo off
setlocal
cd /d "%~dp0"

set "CSG_PWSH=%~dp0runtime\pwsh\pwsh.exe"
set "CSG_RUNTIME_SOURCE=bundled"

if not exist "%CSG_PWSH%" (
  set "CSG_PWSH="
  set "CSG_RUNTIME_SOURCE=path"
  for /f "delims=" %%I in ('where pwsh.exe 2^>nul') do if not defined CSG_PWSH set "CSG_PWSH=%%I"
)

if not defined CSG_PWSH if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" (
  set "CSG_PWSH=%ProgramFiles%\PowerShell\7\pwsh.exe"
  set "CSG_RUNTIME_SOURCE=program-files"
)

if not defined CSG_PWSH (
  echo.
  echo Codex Safety Gate could not find its bundled PowerShell 7 runtime.
  echo Re-extract the complete package, or install PowerShell 7.
  echo.
  pause
  exit /b 1
)

if /i "%~1"=="--smoke" (
  "%CSG_PWSH%" -NoProfile -NonInteractive -File "%~dp0CSG-Launch.ps1" -SmokeTest -RuntimeSource "%CSG_RUNTIME_SOURCE%"
  if errorlevel 1 exit /b 1
  exit /b 0
)

start "Codex Safety Gate" "%CSG_PWSH%" -NoProfile -NonInteractive -WindowStyle Hidden -File "%~dp0CSG-Launch.ps1" -RuntimeSource "%CSG_RUNTIME_SOURCE%"
if errorlevel 1 (
  echo Failed to start Codex Safety Gate.
  pause
  exit /b 1
)
