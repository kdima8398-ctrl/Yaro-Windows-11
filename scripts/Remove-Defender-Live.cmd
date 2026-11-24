@echo off
chcp 65001 >nul
setlocal EnableExtensions EnableDelayedExpansion
title Yaro — Отключение Windows Defender на установленной системе

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo ============================================================================
    echo  [ОШИБКА] Запустите этот скрипт от имени Администратора.
    echo ============================================================================
    echo.
    pause
    exit /b 1
)

echo.
echo ============================================================================
echo   ОТКЛЮЧЕНИЕ WINDOWS DEFENDER НА ЖИВОЙ WINDOWS 11
echo ============================================================================
echo.
echo  ВАЖНО: В Windows 11 включена системная "Защита от подделки" (Tamper Protection).
echo  Пока она включена, операционная система блокирует попытки скриптов
echo  изменить настройки и службы Defender (ошибка "Access is denied").
echo.
echo  ШАГ 1: Сейчас откроется окно настроек Безопасности Windows.
echo  Вам нужно вручную перевести в положение "ВЫКЛ" два тумблера:
echo    1) Защита в режиме реального времени
echo    2) Защита от подделки (Tamper Protection)
echo.
pause

start windowsdefender:

echo.
echo  После того, как вы выключили оба тумблера в открывшемся окне,
echo  нажмите любую клавишу для отключения служб и политик...
pause >nul

echo.
echo  [1/4] Применение политик отключения антивируса...
set "FAILS=0"
call :setdw "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender" DisableAntiSpyware 1
call :setdw "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender" DisableAntiVirus 1
call :setdw "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" DisableRealtimeMonitoring 1
call :setdw "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" DisableBehaviorMonitoring 1
call :setdw "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" DisableOnAccessProtection 1
call :setdw "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" DisableScanOnRealtimeEnable 1
call :setdw "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" DisableIOAVProtection 1
call :setdw "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Systray" HideSystray 1
call :setdw "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Notifications" DisableNotifications 1

echo  [2/4] Отключение системных служб и драйверов (включая MDCoreSvc и webthreatdef)...
set "SERVICES=WinDefend WdNisSvc Sense MDCoreSvc webthreatdefsvc webthreatdefusersvc wscsvc SecurityHealthService WdFilter WdBoot WdNisDrv"
for %%S in (%SERVICES%) do (
    reg query "HKLM\SYSTEM\CurrentControlSet\Services\%%S" >nul 2>&1 && (
        reg add "HKLM\SYSTEM\CurrentControlSet\Services\%%S" /v "Start" /t REG_DWORD /d 4 /f >nul 2>&1
        sc config %%S start= disabled >nul 2>&1
        sc stop %%S >nul 2>&1
    )
)
reg query "HKLM\SYSTEM\CurrentControlSet\Services\webthreatdefusersvc" /v "UserServiceFlags" >nul 2>&1 && reg add "HKLM\SYSTEM\CurrentControlSet\Services\webthreatdefusersvc" /v "UserServiceFlags" /t REG_DWORD /d 0 /f >nul 2>&1
powershell -NoProfile -Command "Get-Service 'webthreatdefusersvc*' -ErrorAction SilentlyContinue | Stop-Service -Force -ErrorAction SilentlyContinue" >nul 2>&1

echo  [3/4] Удаление значка из автозагрузки...
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v "SecurityHealth" /f >nul 2>&1

:: Проверка: что Windows действительно позволила изменить
echo  [4/4] Проверка результата...
set "OFF=0"
set "LEFT="
for %%S in (%SERVICES%) do (
    reg query "HKLM\SYSTEM\CurrentControlSet\Services\%%S" >nul 2>&1
    if not errorlevel 1 (
        reg query "HKLM\SYSTEM\CurrentControlSet\Services\%%S" /v Start 2>nul | find "0x4" >nul && (
            set /a OFF+=1
        ) || (
            set "LEFT=!LEFT! %%S"
        )
    )
)

echo.
echo ============================================================================
if not defined LEFT if "!FAILS!"=="0" (
    echo   ГОТОВО. Отключено служб и драйверов Defender: !OFF!. Все политики записаны.
    echo   Перезагрузите компьютер для окончательного применения изменений.
    echo ============================================================================
    echo.
    pause
    exit /b 0
)
echo   ГОТОВО ЧАСТИЧНО. Отключено служб и драйверов: !OFF!.
if defined LEFT echo   Windows НЕ дала отключить:!LEFT!
if not "!FAILS!"=="0" echo   Не записано политик: !FAILS! - см. строки [x] выше.
echo   Обычно причина - включённая "Защита от подделки". Выключите её
echo   в Безопасности Windows, перезагрузитесь и запустите скрипт снова.
echo ============================================================================
echo.
pause
exit /b 2

:setdw
reg add "%~1" /v "%~2" /t REG_DWORD /d %~3 /f >nul 2>&1 && exit /b 0
echo    [x] Не записано: %~1\%~2 = %~3
set /a FAILS+=1
exit /b 1
