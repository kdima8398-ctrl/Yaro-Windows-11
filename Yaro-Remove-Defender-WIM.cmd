@echo off
chcp 65001 >nul
setlocal EnableExtensions EnableDelayedExpansion
title Yaro — Отключение Windows Defender в образе install.wim (Windows 11 Pro)

:: Проверка прав Администратора
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo ============================================================================
    echo  [ОШИБКА] Запустите этот скрипт от имени Администратора.
    echo  [ERROR]  Please right-click and 'Run as Administrator'.
    echo ============================================================================
    echo.
    pause
    exit /b 1
)

echo.
echo ============================================================================
echo   YARO — ОФЛАЙН ОТКЛЮЧЕНИЕ DEFENDER В ОБРАЗЕ WINDOWS 11 PRO
echo ============================================================================
echo  Этот скрипт изменяет файл install.wim ДО установки системы.
echo  Меняется ТОЛЬКО редакция Windows 11 Pro: именно её ставит autounattend.xml.
echo  Службы (WinDefend, WdNisSvc, Sense, MDCoreSvc, webthreatdef*, wscsvc,
echo  SecurityHealthService) и драйверы (WdFilter, WdBoot, WdNisDrv) отключаются
echo  в реестре образа. Файлы Defender остаются на месте.
echo  В конце скрипт проверяет, что действительно записалось, и пишет результат.
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
    echo  [*] На диске обнаружен install.esd - сжатый образ.
    echo      Файлы ESD нельзя изменять напрямую.
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
echo  Выбран образ:
echo  "%WIM_PATH%"

:: 2. Автоматический выбор редакции: только Windows 11 Pro (EditionId = Professional).
::    Pro N, Pro Education и Pro for Workstations имеют другой EditionId и не подходят.
echo.
echo  Поиск редакции Windows 11 Pro в образе...
set "INDEX="
set "YARO_WIM=%WIM_PATH%"
for /f "usebackq delims=" %%I in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$p = $env:YARO_WIM; foreach ($i in Get-WindowsImage -ImagePath $p) { $d = Get-WindowsImage -ImagePath $p -Index $i.ImageIndex; if ($d.EditionId -eq 'Professional' -and $d.ImageName -like 'Windows 11*') { [Console]::Error.WriteLine('  [+] ' + $d.ImageName + ' - index ' + $d.ImageIndex + ', version ' + $d.Version); $d.ImageIndex; break } }"`) do set "INDEX=%%I"
if not defined INDEX (
    echo.
    echo [ОШИБКА] В образе нет редакции Windows 11 Pro. Образ НЕ изменён.
    echo          Используйте официальный ISO Windows 11 с сайта Microsoft.
    echo.
    pause
    exit /b 1
)

echo.
echo  Внимание: перед продолжением убедитесь, что образ не открыт в других программах.
echo.
set /p "CONFIRM=Изменить редакцию Windows 11 Pro (индекс %INDEX%)? (Y/N): "
if /i not "!CONFIRM!"=="Y" (
    echo Отменено пользователем.
    pause
    exit /b 0
)

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
    echo [ОШИБКА] Не удалось смонтировать образ. Образ НЕ изменён.
    rd /s /q "%MOUNT_DIR%" >nul 2>&1
    pause
    exit /b 1
)

:: 5. Загрузка офлайн-кустов реестра
echo.
echo [2/5] Загрузка реестра смонтированного образа...
reg load HKLM\YARO_SYS "%MOUNT_DIR%\Windows\System32\config\SYSTEM" >nul
if %errorlevel% neq 0 (
    echo [ОШИБКА] Не удалось загрузить куст SYSTEM.
    goto :abort
)

reg load HKLM\YARO_SOFT "%MOUNT_DIR%\Windows\System32\config\SOFTWARE" >nul
if %errorlevel% neq 0 (
    echo [ОШИБКА] Не удалось загрузить куст SOFTWARE.
    goto :abort
)

:: 6. Отключение служб и драйверов Defender (только тех, что есть в образе)
echo.
echo [3/5] Отключение служб, драйверов и политик Defender...
set "FAILS=0"
set "ABSENT="
set "SERVICES=WinDefend WdNisSvc Sense MDCoreSvc webthreatdefsvc webthreatdefusersvc wscsvc SecurityHealthService WdFilter WdBoot WdNisDrv"
for %%S in (%SERVICES%) do (
    reg query "HKLM\YARO_SYS\ControlSet001\Services\%%S" >nul 2>&1
    if errorlevel 1 (
        set "ABSENT=!ABSENT! %%S"
    ) else (
        reg add "HKLM\YARO_SYS\ControlSet001\Services\%%S" /v "Start" /t REG_DWORD /d 4 /f >nul 2>&1 || (
            echo    [x] Не записано: служба %%S, Start=4
            set /a FAILS+=1
        )
    )
)
reg query "HKLM\YARO_SYS\ControlSet001\Services\webthreatdefusersvc" /v "UserServiceFlags" >nul 2>&1 && call :setdw "HKLM\YARO_SYS\ControlSet001\Services\webthreatdefusersvc" UserServiceFlags 0

:: Политики отключения антивируса и защиты реального времени
call :setdw "HKLM\YARO_SOFT\Policies\Microsoft\Windows Defender" DisableAntiSpyware 1
call :setdw "HKLM\YARO_SOFT\Policies\Microsoft\Windows Defender" DisableAntiVirus 1
call :setdw "HKLM\YARO_SOFT\Policies\Microsoft\Windows Defender\Real-Time Protection" DisableRealtimeMonitoring 1
call :setdw "HKLM\YARO_SOFT\Policies\Microsoft\Windows Defender\Real-Time Protection" DisableBehaviorMonitoring 1
call :setdw "HKLM\YARO_SOFT\Policies\Microsoft\Windows Defender\Real-Time Protection" DisableOnAccessProtection 1
call :setdw "HKLM\YARO_SOFT\Policies\Microsoft\Windows Defender\Real-Time Protection" DisableScanOnRealtimeEnable 1
call :setdw "HKLM\YARO_SOFT\Policies\Microsoft\Windows Defender\Real-Time Protection" DisableIOAVProtection 1

:: Отключение телеметрии SpyNet
call :setdw "HKLM\YARO_SOFT\Policies\Microsoft\Windows Defender\Spynet" SpynetReporting 0
call :setdw "HKLM\YARO_SOFT\Policies\Microsoft\Windows Defender\Spynet" SubmitSamplesConsent 2

:: Отключение значка безопасности и уведомлений
call :setdw "HKLM\YARO_SOFT\Policies\Microsoft\Windows Defender Security Center\Systray" HideSystray 1
call :setdw "HKLM\YARO_SOFT\Policies\Microsoft\Windows Defender Security Center\Notifications" DisableNotifications 1
reg delete "HKLM\YARO_SOFT\Microsoft\Windows\CurrentVersion\Run" /v "SecurityHealth" /f >nul 2>&1

:: Отключение Tamper Protection в настройках характеристик
call :setdw "HKLM\YARO_SOFT\Microsoft\Windows Defender\Features" TamperProtection 0

:: Проверка: что действительно записалось в реестр образа
echo.
echo  Проверка записанных значений...
set "OFF=0"
set "LEFT="
for %%S in (%SERVICES%) do (
    reg query "HKLM\YARO_SYS\ControlSet001\Services\%%S" >nul 2>&1
    if not errorlevel 1 (
        reg query "HKLM\YARO_SYS\ControlSet001\Services\%%S" /v Start 2>nul | find "0x4" >nul && (
            set /a OFF+=1
        ) || (
            set "LEFT=!LEFT! %%S"
        )
    )
)

:: 7. Выгрузка кустов. Если куст не выгружается, изменения нельзя сохранить безопасно.
echo.
echo [4/5] Сохранение и выгрузка веток реестра...
call :unload HKLM\YARO_SYS || (
    echo [ОШИБКА] Куст SYSTEM занят другой программой и не выгружается.
    goto :abort
)
call :unload HKLM\YARO_SOFT || (
    echo [ОШИБКА] Куст SOFTWARE занят другой программой и не выгружается.
    goto :abort
)

:: 8. Сохранение изменений и размонтирование WIM
echo.
echo [5/5] Сохранение изменений в install.wim...
dism /Unmount-Wim /MountDir:"%MOUNT_DIR%" /Commit
if %errorlevel% neq 0 (
    echo.
    echo [ОШИБКА] Не удалось сохранить изменения в образ. Проверьте место на флешке
    echo          и запустите скрипт снова.
    pause
    exit /b 1
)
rd /s /q "%MOUNT_DIR%" >nul 2>&1

:: 9. Честный итог
echo.
echo ============================================================================
if not defined LEFT if "!FAILS!"=="0" (
    echo   ГОТОВО. Windows 11 Pro, индекс %INDEX%: отключено служб и драйверов: !OFF!.
    echo   Все политики записаны. Образ можно использовать для чистой установки.
    if defined ABSENT echo   В этой сборке Windows нет служб:!ABSENT!
    echo ============================================================================
    echo.
    pause
    exit /b 0
)
echo   ГОТОВО С ПРЕДУПРЕЖДЕНИЯМИ. Windows 11 Pro, индекс %INDEX%.
echo   Отключено служб и драйверов: !OFF!.
if defined LEFT echo   НЕ отключены:!LEFT!
if not "!FAILS!"=="0" echo   Не записано параметров: !FAILS! - см. строки [x] выше.
if defined ABSENT echo   В этой сборке Windows нет служб:!ABSENT!
echo ============================================================================
echo.
pause
exit /b 2

:: ---------------------------------------------------------------------------
:: Подпрограммы
:: ---------------------------------------------------------------------------
:setdw
reg add "%~1" /v "%~2" /t REG_DWORD /d %~3 /f >nul 2>&1 && exit /b 0
echo    [x] Не записано: %~1\%~2 = %~3
set /a FAILS+=1
exit /b 1

:unload
for /l %%N in (1,1,5) do (
    reg unload %1 >nul 2>&1 && exit /b 0
    ping -n 3 127.0.0.1 >nul
)
exit /b 1

:abort
echo.
echo  [*] Изменения НЕ сохранены. Образ размонтируется без записи...
reg unload HKLM\YARO_SYS >nul 2>&1
reg unload HKLM\YARO_SOFT >nul 2>&1
dism /Unmount-Wim /MountDir:"%MOUNT_DIR%" /Discard >nul 2>&1
rd /s /q "%MOUNT_DIR%" >nul 2>&1
echo.
pause
exit /b 1
