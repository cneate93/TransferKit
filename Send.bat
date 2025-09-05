@echo off
setlocal enableextensions
REM --- always run from this folder ---
cd /d "%~dp0"
title TransferKit - Sender

REM --- launcher log (timestamped) ---
set "LOGDIR=logs\launch_logs"
if not exist "%LOGDIR%" mkdir "%LOGDIR%"
for /f "tokens=1-4 delims=/ " %%a in ("%date%") do set d=%%d%%b%%c
for /f "tokens=1-2 delims=:." %%a in ("%time%") do set t=%%a%%b
set "STAMP=%d%-%t%"
set "LAUNCH=%LOGDIR%\send-launch-%STAMP%.log"

call :log "Launcher started (cwd=%cd%)"

REM --- sanity checks ---
if not exist "rclone.exe" (
  call :log "[ERROR] rclone.exe not found in %cd%"
  echo [ERROR] rclone.exe not found in "%cd%"
  pause
  exit /b 1
)
if not exist "Send.ps1" (
  call :log "[ERROR] Send.ps1 not found in %cd%"
  echo [ERROR] Send.ps1 not found in "%cd%"
  pause
  exit /b 1
)

REM --- prefer pwsh if available; fallback to Windows PowerShell ---
where /q pwsh.exe
if %errorlevel%==0 (
  set "PS=pwsh.exe"
) else (
  set "PS=powershell.exe"
)

REM --- run (STA so dialogs work), no redirection = live stats visible ---
call :log "Invoking %PS% -STA Send.ps1 %*"
"%PS%" -STA -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\Send.ps1" %*
set "RC=%ERRORLEVEL%"
call :log "Exit code: %RC%"

echo.
if not "%RC%"=="0" (
  echo Send.ps1 returned error %RC%. See ".\logs\send_logs" and "%LAUNCH%" for details.
  pause
)

endlocal & exit /b %RC%

:log
echo [%date% %time%] %~1>>"%LAUNCH%"
goto :eof
