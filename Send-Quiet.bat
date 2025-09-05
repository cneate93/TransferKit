@echo off
setlocal
REM --- always run from this folder ---
cd /d "%~dp0"

REM --- launch log setup ---
set "LOGDIR=logs\launch_logs"
if not exist "%LOGDIR%" mkdir "%LOGDIR%"
set "STAMP=%DATE:~-4%%DATE:~4,2%%DATE:~7,2%-%TIME:~0,2%%TIME:~3,2%%TIME:~6,2%"
set "STAMP=%STAMP: =0%"
set "LOGFILE=%LOGDIR%\send-launch-%STAMP%.log"

echo [%date% %time%] Sender launcher starting... > "%LOGFILE%"

REM --- sanity checks ---
if not exist "rclone.exe" (
  echo rclone.exe not found in %cd% >> "%LOGFILE%"
  echo ERROR: rclone.exe not found in %cd%
  pause
  exit /b 1
)
if not exist "Send.ps1" (
  echo Send.ps1 not found in %cd% >> "%LOGFILE%"
  echo ERROR: Send.ps1 not found in %cd%
  pause
  exit /b 1
)

REM --- run Send.ps1 (forward any args you pass to the .bat) ---
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\Send.ps1" %*  1>>"%LOGFILE%" 2>&1
set "RC=%ERRORLEVEL%"

echo [%date% %time%] Sender launcher exit code %RC% >> "%LOGFILE%"

if not "%RC%"=="0" (
  echo Send.ps1 returned error %RC%. See "%LOGFILE%" and logs\send_logs for details.
  pause
) else (
  echo Transfer complete. See "%LOGFILE%" and logs\send_logs for copy log.
)
endlocal
