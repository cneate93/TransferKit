@echo off
setlocal
cd /d "%~dp0"

rem --- log setup ---
set LOGDIR=logs\launch_logs
if not exist "%LOGDIR%" mkdir "%LOGDIR%"
set LOGFILE=%LOGDIR%\receiver-launch-%DATE:~-4%%DATE:~4,2%%DATE:~7,2%-%TIME:~0,2%%TIME:~3,2%%TIME:~6,2%.log
set LOGFILE=%LOGFILE: =0%

echo [%date% %time%] Receiver launcher starting... > "%LOGFILE%"

rem --- sanity checks ---
if not exist "rclone.exe" (
  echo rclone.exe not found in %cd% >> "%LOGFILE%"
  echo ERROR: rclone.exe not found in %cd%
  pause
  exit /b 1
)
if not exist "Receiver.ps1" (
  echo Receiver.ps1 not found in %cd% >> "%LOGFILE%"
  echo ERROR: Receiver.ps1 not found in %cd%
  pause
  exit /b 1
)

rem --- run script (bypass policy) ---
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\Receiver.ps1" ^
  *>>"%LOGFILE%"

set RC=%ERRORLEVEL%
echo [%date% %time%] Receiver launcher exit code %RC% >> "%LOGFILE%"

if %RC% NEQ 0 (
  echo Receiver.ps1 returned error %RC%. See "%LOGFILE%"
  pause
) else (
  echo Receiver started. See "%LOGFILE%" and logs\receiver_logs for server log.
)
endlocal
