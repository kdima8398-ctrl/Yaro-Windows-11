@echo off
chcp 65001 >nul
setlocal EnableExtensions EnableDelayedExpansion
title Yaro — Вырезание / Отключение Windows Defender в образе install.wim

:: Проверка прав Администратора
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo ============================================================================
    echo  [ОШИБКА] Запустите этот скрипт от имени Администратора!
    echo  [ERROR]  Please right-click and 'Run as Administrator'!
    echo ============================================================================
    echo.
    pause
    exit /b 1
)

echo.
echo ============================================================================
echo   YARO — ОФЛАЙН ВЫРЕЗАНИЕ / ОТКЛЮЧЕНИЕ DEFENDER ИЗ ОБРАЗА WINDOWS 11
echo ============================================================================
echo  Этот скрипт модифицирует файл install.wim ДО установки системы.
echo  Все службы (WinDefend, WdNisSvc, Sense, SecurityHealth) и драйверы
echo  перехвата (WdFilter, WdBoot) отключаются в системном кусте реестра.
echo.
echo  В результате при установке Windows:
echo   * Defender НЕ запустится ни разу (0 процессов, 0 нагрузки на CPU/диск);
echo   * Защита от подделки (Tamper Protection) НЕ заблокирует настройки;
echo   * Не потребуется вручную заходить в Безопасность Windows после установки.
echo ============================================================================
echo.

:: 1. Поиск install.wim на флешках или запрос пути
set "WIM_PATH="

:: Проверяем смонтированные диски на наличие sources\install.wim
for %%D in (D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
    if exist "%%D:\sources\install.wim" (
        set "WIM_PATH=%%D:\sources\install.wim"
        echo  [+] Обнаружен установочный образ на флешке/диске: %%D:\sources\install.wim
        goto :found_wim
    )
)

:: Проверяем локальные папки сборки
if exist "%~dp0..\win save\Win11_MASTER_BACKUP_EDITABLE\install_master_pro.wim" (
    set "WIM_PATH=%~dp0..\win save\Win11_MASTER_BACKUP_EDITABLE\install_master_pro.wim"
    echo  [+] Обнаружен локальный мастер-образ: !WIM_PATH!
    goto :found_wim
)

:ask_path
echo Введите полный путь к файлу install.wim (или букву диска флешки, например E:):
set /p "USER_INPUT=> "
set "USER_INPUT=!USER_INPUT:"=!"

if exist "!USER_INPUT!\sources\install.wim" (
    set "WIM_PATH=!USER_INPUT!\sources\install.wim"
    goto :found_wim
)
if exist "!USER_INPUT!" (
    set "WIM_PATH=!USER_INPUT!"
    goto :found_wim
)

:: Проверка на install.esd
if exist "!USER_INPUT!\sources\install.esd" (
    echo.
    echo  [!] На диске обнаружен install.esd (сжатый образ).
    echo      Файлы ESD защищены от прямой модификации.
    echo      Экспортируйте его в WIM через команду:
    echo      dism /Export-Image /SourceImageFile:"!USER_INPUT!\sources\install.esd" /SourceIndex:1 /DestinationImageFile:"!USER_INPUT!\sources\install.wim" /Compress:max
    echo.
    pause
    goto :ask_path
)

echo [ОШИБКА] Файл не найден: "!USER_INPUT!"
goto :ask_path

:found_wim
echo.
echo  Выбран целевой образ:
echo  "%WIM_PATH%"
echo.
echo  Внимание: перед продолжением убедитесь, что образ не открыт в других программах.
echo.
set /p "CONFIRM=Продолжить модификацию? (Y/N): "
if /i not "!CONFIRM!"=="Y" (
    echo Отменено пользователем.
    pause
    exit /b 0
)

:: 2. Определение индекса (по умолчанию 1)
set "INDEX=1"
echo.
echo  Проверка редакций в образе...
dism /Get-WimInfo /WimFile:"%WIM_PATH%"
echo.
set /p "INDEX=Введите номер индекса для модификации (обычно 1 или номер Pro-редакции, Enter=1): "
if "!INDEX!"=="" set "INDEX=1"

:: 3. Создание папки монтирования
set "MOUNT_DIR=%SystemDrive%\Yaro_Wim_Mount"
if exist "%MOUNT_DIR%" (
    echo  Очистка старой папки монтирования...
    dism /Unmount-Wim /MountDir:"%MOUNT_DIR%" /Discard >nul 2>&1
    rd /s /q "%MOUNT_DIR%" >nul 2>&1
)
mkdir "%MOUNT_DIR%"

:: 4. Монтирование WIM
echo.
echo [1/5] Монтирование образа Windows (это займет 1-3 минуты)...
dism /Mount-Wim /WimFile:"%WIM_PATH%" /Index:%INDEX% /MountDir:"%MOUNT_DIR%"
if %errorlevel% neq 0 (
    echo.
    echo [ОШИБКА] Не удалось смонтировать образ!
    rd /s /q "%MOUNT_DIR%" >nul 2>&1
    pause
    exit /b 1
)

:: 5. Загрузка офлайн-кустов реестра
echo.
echo [2/5] Загрузка реестра смонтированного образа...
reg load HKLM\YARO_SYS "%MOUNT_DIR%\Windows\System32\config\SYSTEM" >nul
if %errorlevel% neq 0 (
    echo [ОШИБКА] Не удалось загрузить куст SYSTEM!
    goto :abort
)

reg load HKLM\YARO_SOFT "%MOUNT_DIR%\Windows\System32\config\SOFTWARE" >nul
if %errorlevel% neq 0 (
    echo [ОШИБКА] Не удалось загрузить куст SOFTWARE!
    reg unload HKLM\YARO_SYS >nul 2>&1
    goto :abort
)

:: 6. Отключение служб и драйверов Defender
echo.
echo [3/5] Отключение всех служб, драйверов перехвата и компонентов Defender...

:: Службы: Start = 4 (Disabled)
reg add "HKLM\YARO_SYS\ControlSet001\Services\WinDefend" /v "Start" /t REG_DWORD /d 4 /f >nul
reg add "HKLM\YARO_SYS\ControlSet001\Services\WdNisSvc" /v "Start" /t REG_DWORD /d 4 /f >nul
reg add "HKLM\YARO_SYS\ControlSet001\Services\Sense" /v "Start" /t REG_DWORD /d 4 /f >nul
reg add "HKLM\YARO_SYS\ControlSet001\Services\SecurityHealthService" /v "Start" /t REG_DWORD /d 4 /f >nul

:: Драйверы уровня ядра (перехват файлов и ранняя загрузка)
reg add "HKLM\YARO_SYS\ControlSet001\Services\WdFilter" /v "Start" /t REG_DWORD /d 4 /f >nul
reg add "HKLM\YARO_SYS\ControlSet001\Services\WdBoot" /v "Start" /t REG_DWORD /d 4 /f >nul
reg add "HKLM\YARO_SYS\ControlSet001\Services\WdNisDrv" /v "Start" /t REG_DWORD /d 4 /f >nul

:: Политики отключения антивируса и защиты реального времени
reg add "HKLM\YARO_SOFT\Policies\Microsoft\Windows Defender" /v "DisableAntiSpyware" /t REG_DWORD /d 1 /f >nul
reg add "HKLM\YARO_SOFT\Policies\Microsoft\Windows Defender" /v "DisableAntiVirus" /t REG_DWORD /d 1 /f >nul
reg add "HKLM\YARO_SOFT\Policies\Microsoft\Windows Defender\Real-Time Protection" /v "DisableRealtimeMonitoring" /t REG_DWORD /d 1 /f >nul
reg add "HKLM\YARO_SOFT\Policies\Microsoft\Windows Defender\Real-Time Protection" /v "DisableBehaviorMonitoring" /t REG_DWORD /d 1 /f >nul
reg add "HKLM\YARO_SOFT\Policies\Microsoft\Windows Defender\Real-Time Protection" /v "DisableOnAccessProtection" /t REG_DWORD /d 1 /f >nul
reg add "HKLM\YARO_SOFT\Policies\Microsoft\Windows Defender\Real-Time Protection" /v "DisableScanOnRealtimeEnable" /t REG_DWORD /d 1 /f >nul
reg add "HKLM\YARO_SOFT\Policies\Microsoft\Windows Defender\Real-Time Protection" /v "DisableIOAVProtection" /t REG_DWORD /d 1 /f >nul

:: Отключение телеметрии SpyNet
reg add "HKLM\YARO_SOFT\Policies\Microsoft\Windows Defender\Spynet" /v "SpynetReporting" /t REG_DWORD /d 0 /f >nul
reg add "HKLM\YARO_SOFT\Policies\Microsoft\Windows Defender\Spynet" /v "SubmitSamplesConsent" /t REG_DWORD /d 2 /f >nul

:: Отключение значка безопасности и уведомлений
reg add "HKLM\YARO_SOFT\Policies\Microsoft\Windows Defender Security Center\Systray" /v "HideSystray" /t REG_DWORD /d 1 /f >nul
reg add "HKLM\YARO_SOFT\Policies\Microsoft\Windows Defender Security Center\Notifications" /v "DisableNotifications" /t REG_DWORD /d 1 /f >nul
reg delete "HKLM\YARO_SOFT\Microsoft\Windows\CurrentVersion\Run" /v "SecurityHealth" /f >nul 2>&1

:: Отключение Tamper Protection в настройках характеристик
reg add "HKLM\YARO_SOFT\Microsoft\Windows Defender\Features" /v "TamperProtection" /t REG_DWORD /d 0 /f >nul

:: 7. Выгрузка кустов
echo.
echo [4/5] Сохранение и выгрузка веток реестра...
reg unload HKLM\YARO_SYS >nul 2>&1
reg unload HKLM\YARO_SOFT >nul 2>&1

:: 8. Сохранение изменений и размонтирование WIM
echo.
echo [5/5] Сохранение изменений в install.wim (коммит образа)...
dism /Unmount-Wim /MountDir:"%MOUNT_DIR%" /Commit
if %errorlevel% neq 0 (
    echo [ОШИБКА] Не удалось сохранить изменения при размонтировании!
    pause
    exit /b 1
)

rd /s /q "%MOUNT_DIR%" >nul 2>&1

echo.
echo ============================================================================
echo   УСПЕШНО! Windows Defender полностью отключен в вашем образе!
echo ============================================================================
echo  Теперь можно использовать этот install.wim / флешку для чистой установки.
echo  Никаких служб Защитника запущено не будет.
echo ============================================================================
echo.
pause
exit /b 0

:abort
echo.
echo  [!] Произошла ошибка. Отмена изменений и размонтирование...
dism /Unmount-Wim /MountDir:"%MOUNT_DIR%" /Discard >nul 2>&1
rd /s /q "%MOUNT_DIR%" >nul 2>&1
echo.
pause
exit /b 1
