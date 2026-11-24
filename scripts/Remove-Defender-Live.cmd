@echo off
chcp 65001 >nul
setlocal EnableExtensions EnableDelayedExpansion
title Yaro — Отключение Windows Defender на установленной системе

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo ============================================================================
    echo  [ОШИБКА] Запустите этот скрипт от имени Администратора!
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
start ms-settings:windowsdefender

echo.
echo  После того, как вы выключили оба тумблера в открывшемся окне,
echo  нажмите любую клавишу для отключения служб и политик...
pause >nul

echo.
echo  [1/3] Применение политик отключения антивируса...
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender" /v "DisableAntiSpyware" /t REG_DWORD /d 1 /f >nul
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender" /v "DisableAntiVirus" /t REG_DWORD /d 1 /f >nul
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v "DisableRealtimeMonitoring" /t REG_DWORD /d 1 /f >nul
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v "DisableBehaviorMonitoring" /t REG_DWORD /d 1 /f >nul
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v "DisableOnAccessProtection" /t REG_DWORD /d 1 /f >nul
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v "DisableScanOnRealtimeEnable" /t REG_DWORD /d 1 /f >nul
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection" /v "DisableIOAVProtection" /t REG_DWORD /d 1 /f >nul
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Systray" /v "HideSystray" /t REG_DWORD /d 1 /f >nul
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Notifications" /v "DisableNotifications" /t REG_DWORD /d 1 /f >nul

echo  [2/3] Отключение системных служб и драйверов...
for %%S in (WinDefend WdNisSvc Sense SecurityHealthService WdFilter WdBoot WdNisDrv) do (
    sc config %%S start= disabled >nul 2>&1
    sc stop %%S >nul 2>&1
)

echo  [3/3] Удаление значка из автозагрузки...
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" /v "SecurityHealth" /f >nul 2>&1

echo.
echo ============================================================================
echo   ГОТОВО! Defender и связанные службы переведены в состояние Disabled.
echo   Перезагрузите компьютер для окончательного применения изменений.
echo ============================================================================
echo.
pause
