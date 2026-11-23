@echo off
setlocal DisableDelayedExpansion
rem Run this launcher from the account that should receive the user settings.
set "YARO_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "YARO_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
set "YARO_LOGS=%SystemRoot%\Setup\Scripts\Yaro"
set "YARO_USER_LOG=%LOCALAPPDATA%\Yaro\FirstLogon.log"

title Yaro - apply settings
echo.
echo  Yaro will remove apps, change services and many Windows settings.
echo  Close this window now if you have not read README.md.
echo.
pause
set "YARO_PARTIAL="

set "YARO_STAGE=System settings"
echo [1/2] %YARO_STAGE% and restore point (this can take several minutes)...
"%YARO_PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Specialize.ps1" -Live
set "YARO_RESULT=%ERRORLEVEL%"
if "%YARO_RESULT%"=="2" (
  set "YARO_PARTIAL=1"
) else if not "%YARO_RESULT%"=="0" goto :failed

set "YARO_STAGE=Settings of the current user"
echo [2/2] %YARO_STAGE%...
"%YARO_PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\FirstLogon.ps1"
set "YARO_RESULT=%ERRORLEVEL%"
if "%YARO_RESULT%"=="2" (
  set "YARO_PARTIAL=1"
) else if not "%YARO_RESULT%"=="0" goto :failed

echo.
echo  System log: "%YARO_LOGS%\Specialize.log"
echo  User log: "%YARO_USER_LOG%"
if defined YARO_PARTIAL (
  echo  Finished with warnings or failed settings. Review the logs.
  pause
  exit /b 2
)
echo  Finished. Restart Windows to finish applying the settings.
pause
exit /b 0

:failed
echo.
echo  %YARO_STAGE% stopped with exit code %YARO_RESULT%.
echo  System log: "%YARO_LOGS%\Specialize.log"
echo  User log: "%YARO_USER_LOG%"
pause
exit /b %YARO_RESULT%
