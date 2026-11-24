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

set "YARO_SELF=%~f0"
set "SERVICES=WinDefend WdNisSvc Sense MDCoreSvc webthreatdefsvc webthreatdefusersvc wscsvc SecurityHealthService WdFilter WdBoot WdNisDrv"

echo.
echo ============================================================================
echo   YARO — ОФЛАЙН ОТКЛЮЧЕНИЕ DEFENDER В ОБРАЗЕ WINDOWS 11 PRO
echo ============================================================================
echo  Этот скрипт изменяет файл install.wim ДО установки системы.
echo  Меняется ТОЛЬКО редакция Windows 11 Pro: именно её ставит autounattend.xml.
echo  Отключаются ВСЕ службы (WinDefend, WdNisSvc, Sense, MDCoreSvc,
echo  webthreatdef*, wscsvc, SecurityHealthService), драйверы (WdFilter, WdBoot,
echo  WdNisDrv), политики и TamperProtection (со снятием защиты ACL SYSTEM).
echo  В конце скрипт проверяет, что действительно записалось, и пишет результат.
echo ============================================================================
echo.

:: 1. Поиск доступного для записи install.wim на флешках/дисках или запрос пути
set "WIM_PATH="
set "YARO_SCRIPT_DIR=%~dp0"
for /f "usebackq tokens=1,* delims=|" %%A in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$c=((Get-Content -LiteralPath $env:YARO_SELF -Raw -Encoding UTF8) -split '(?m)^:: __YARO_PS_START__\r?$',2)[1]; & ([scriptblock]::Create($c)) -Mode FindWim"`) do (
    if "%%A"=="WIM" (
        set "WIM_PATH=%%B"
        echo  [+] Обнаружен доступный для записи образ: %%B
        goto :found_wim
    )
    if "%%A"=="SKIP_RO" (
        echo  [i] Пропущен образ только для чтения ^(смонтированный ISO^): %%B
    )
    if "%%A"=="ESD" (
        echo  [*] На диске %%B обнаружен сжатый install.esd ^(без install.wim^).
    )
)

:ask_path
echo.
echo Введите полный путь к файлу install.wim (или букву диска флешки, например E:):
set /p "USER_INPUT=> "
if not defined USER_INPUT goto :ask_path
set "USER_INPUT=!USER_INPUT:"=!"
if "!USER_INPUT!"=="" goto :ask_path

set "YARO_INPUT=%USER_INPUT%"
for /f "usebackq tokens=1,* delims=|" %%A in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$c=((Get-Content -LiteralPath $env:YARO_SELF -Raw -Encoding UTF8) -split '(?m)^:: __YARO_PS_START__\r?$',2)[1]; & ([scriptblock]::Create($c)) -Mode ResolveInput"`) do (
    if "%%A"=="WIM" (
        set "WIM_PATH=%%B"
        goto :found_wim
    )
    if "%%A"=="ESD" (
        echo.
        echo  [*] Обнаружен install.esd - сжатый образ: "%%B"
        echo      Файлы ESD нельзя изменять напрямую. Экспортируйте его в WIM:
        echo      dism /Export-Image /SourceImageFile:"%%B" /SourceIndex:1 /DestinationImageFile:"%%~dpBinstall.wim" /Compress:max
        echo.
        pause
        goto :ask_path
    )
    if "%%A"=="READONLY" (
        echo.
        echo  [ОШИБКА] Образ "%%B" находится на носителе только для чтения ^(ISO/DVD^)
        echo           или имеет атрибут Read-Only. Запишите образ на флешку через Rufus
        echo           или скопируйте install.wim на жёсткий диск.
        echo.
        goto :ask_path
    )
    if "%%A"=="ERR" (
        echo  [ОШИБКА] %%B
        goto :ask_path
    )
)
echo  [ОШИБКА] Не удалось распознать путь: "!USER_INPUT!"
goto :ask_path

:found_wim
echo.
echo  Выбран образ:
echo  "%WIM_PATH%"

:: 2. Автоматический выбор редакции: только Windows 11 Pro (EditionId = Professional, Build >= 22000).
echo.
echo  Поиск редакции Windows 11 Pro в образе...
set "INDEX="
set "YARO_WIM=%WIM_PATH%"
for /f "usebackq delims=" %%I in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$c=((Get-Content -LiteralPath $env:YARO_SELF -Raw -Encoding UTF8) -split '(?m)^:: __YARO_PS_START__\r?$',2)[1]; & ([scriptblock]::Create($c)) -Mode GetProIndex"`) do set "INDEX=%%I"
if not defined INDEX (
    echo.
    echo [ОШИБКА] В образе нет редакции Windows 11 Pro ^(EditionId = Professional^). Образ НЕ изменён.
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

:: 6. Разблокировка защищённых ключей SYSTEM (wscsvc, SecurityHealthService, Features) и отключение Defender
echo.
echo [3/5] Снятие защиты ACL с системных ключей и отключение Defender...
set "YARO_SERVICES=%SERVICES%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$c=((Get-Content -LiteralPath $env:YARO_SELF -Raw -Encoding UTF8) -split '(?m)^:: __YARO_PS_START__\r?$',2)[1]; & ([scriptblock]::Create($c)) -Mode UnlockOffline"
if %errorlevel% neq 0 (
    echo  [!] Предупреждение: часть прав ACL не удалось обновить автоматически.
)

set "FAILS=0"
set "ABSENT="
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
reg query "HKLM\YARO_SOFT\Microsoft\Windows Defender\UX Configuration" >nul 2>&1 && call :setdw "HKLM\YARO_SOFT\Microsoft\Windows Defender\UX Configuration" Notification_Suppress 1
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
reg query "HKLM\YARO_SOFT\Microsoft\Windows Defender\Features" /v TamperProtection 2>nul | find "0x0" >nul || (
    set "LEFT=!LEFT! TamperProtection"
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
    echo   ГОТОВО! Windows 11 Pro, индекс %INDEX%: отключено служб и драйверов: !OFF!.
    echo   TamperProtection = 0 и все политики Defender записаны без ошибок.
    echo   Образ можно использовать для чистой установки.
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

:: __YARO_PS_START__
param(
  [Parameter(Mandatory)]
  [ValidateSet('FindWim', 'ResolveInput', 'GetProIndex', 'UnlockOffline')]
  [string]$Mode
)

$ErrorActionPreference = 'Stop'

function Test-WritableWimPath([string]$FilePath) {
  if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) { return 'MISSING' }
  $root = [IO.Path]::GetPathRoot($FilePath)
  if ($root) {
    $drive = [IO.DriveInfo]::new($root)
    if ($drive.DriveType -eq 'CDRom') { return 'READONLY' }
  }
  $item = Get-Item -LiteralPath $FilePath -Force
  if ($item.IsReadOnly) { return 'READONLY' }
  return 'OK'
}

switch ($Mode) {
  'FindWim' {
    $esdDrives = @()
    foreach ($letter in (68..90 | ForEach-Object { [char]$_ })) {
      $root = "${letter}:\"
      $drive = [IO.DriveInfo]::new($root)
      if (-not $drive.IsReady) { continue }
      $wim = Join-Path $root 'sources\install.wim'
      $esd = Join-Path $root 'sources\install.esd'
      if (Test-Path -LiteralPath $wim -PathType Leaf) {
        if ($drive.DriveType -eq 'CDRom' -or (Get-Item -LiteralPath $wim -Force).IsReadOnly) {
          "SKIP_RO|$wim"
          continue
        }
        "WIM|$wim"
        return
      }
      if ($drive.DriveType -ne 'CDRom' -and (Test-Path -LiteralPath $esd -PathType Leaf)) {
        $esdDrives += "${letter}:"
      }
    }
    if ($env:YARO_SCRIPT_DIR) {
      $localMaster = [IO.Path]::GetFullPath((Join-Path $env:YARO_SCRIPT_DIR '..\win save\Win11_MASTER_BACKUP_EDITABLE\install_master_pro.wim'))
      if ((Test-WritableWimPath $localMaster) -eq 'OK') {
        "WIM|$localMaster"
        return
      }
    }
    foreach ($d in $esdDrives) { "ESD|$d" }
    return
  }

  'ResolveInput' {
    $raw = [string]$env:YARO_INPUT
    $raw = $raw.Trim().Trim('"')
    if (-not $raw) { "ERR|Пустой путь."; return }

    if ($raw -match '^[A-Za-z]:?$') {
      $raw = $raw.Substring(0, 1).ToUpper() + ':\'
    }

    if (Test-Path -LiteralPath $raw -PathType Container) {
      $candidates = @(
        (Join-Path $raw 'sources\install.wim'),
        (Join-Path $raw 'install.wim')
      )
      foreach ($c in $candidates) {
        $st = Test-WritableWimPath $c
        if ($st -eq 'OK') { "WIM|$c"; return }
        if ($st -eq 'READONLY') { "READONLY|$c"; return }
      }
      foreach ($e in (Join-Path $raw 'sources\install.esd'), (Join-Path $raw 'install.esd')) {
        if (Test-Path -LiteralPath $e -PathType Leaf) { "ESD|$e"; return }
      }
      "ERR|В папке `"$raw`" не найден файл install.wim."
      return
    }

    if (Test-Path -LiteralPath $raw -PathType Leaf) {
      if ($raw -like '*.esd') { "ESD|$raw"; return }
      $st = Test-WritableWimPath $raw
      if ($st -eq 'READONLY') { "READONLY|$raw"; return }
      "WIM|$raw"
      return
    }

    "ERR|Файл или папка не найдены: `"$raw`""
    return
  }

  'GetProIndex' {
    $p = $env:YARO_WIM
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { return }
    foreach ($i in Get-WindowsImage -ImagePath $p) {
      $d = Get-WindowsImage -ImagePath $p -Index $i.ImageIndex
      $ver = $null
      try { $ver = [version]$d.Version } catch { }
      $isWin11 = ($d.ImageName -like 'Windows 11*') -or ($ver -and $ver.Major -ge 10 -and $ver.Build -ge 22000)
      if ($d.EditionId -eq 'Professional' -and $isWin11) {
        [Console]::Error.WriteLine("  [+] $($d.ImageName) - index $($d.ImageIndex), version $($d.Version)")
        $d.ImageIndex
        break
      }
    }
    return
  }

  'UnlockOffline' {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class YaroWimPriv {
  [DllImport("advapi32.dll", SetLastError = true)]
  static extern bool OpenProcessToken(IntPtr ProcessHandle, uint DesiredAccess, out IntPtr TokenHandle);
  [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
  static extern bool LookupPrivilegeValue(string lpSystemName, string lpName, out LUID lpLuid);
  [DllImport("advapi32.dll", SetLastError = true)]
  static extern bool AdjustTokenPrivileges(IntPtr TokenHandle, bool DisableAllPrivileges, ref TOKEN_PRIVILEGES NewState, int BufferLength, IntPtr PreviousState, IntPtr ReturnLength);
  [DllImport("kernel32.dll", SetLastError = true)]
  static extern bool CloseHandle(IntPtr hObject);

  [StructLayout(LayoutKind.Sequential)] struct LUID { public uint LowPart; public int HighPart; }
  [StructLayout(LayoutKind.Sequential)] struct LUID_AND_ATTRIBUTES { public LUID Luid; public uint Attributes; }
  [StructLayout(LayoutKind.Sequential)] struct TOKEN_PRIVILEGES { public uint PrivilegeCount; public LUID_AND_ATTRIBUTES Privileges; }

  public static bool Enable(string name) {
    IntPtr hTok = IntPtr.Zero;
    try {
      if (!OpenProcessToken(System.Diagnostics.Process.GetCurrentProcess().Handle, 0x0028, out hTok)) return false;
      LUID luid;
      if (!LookupPrivilegeValue(null, name, out luid)) return false;
      TOKEN_PRIVILEGES tp = new TOKEN_PRIVILEGES { PrivilegeCount = 1, Privileges = new LUID_AND_ATTRIBUTES { Luid = luid, Attributes = 2 } };
      if (!AdjustTokenPrivileges(hTok, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero)) return false;
      return Marshal.GetLastWin32Error() == 0;
    } finally {
      if (hTok != IntPtr.Zero) CloseHandle(hTok);
    }
  }
}
'@ -ErrorAction Stop

    if (-not [YaroWimPriv]::Enable('SeTakeOwnershipPrivilege')) {
      throw 'Не удалось активировать привилегию SeTakeOwnershipPrivilege.'
    }
    [void][YaroWimPriv]::Enable('SeRestorePrivilege')

    $adminSid = [System.Security.Principal.SecurityIdentifier]'S-1-5-32-544'
    $inherit = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
    $prop = [System.Security.AccessControl.PropagationFlags]::None
    $allow = [System.Security.AccessControl.AccessControlType]::Allow
    $full = [System.Security.AccessControl.RegistryRights]::FullControl
    $fullRule = New-Object System.Security.AccessControl.RegistryAccessRule($adminSid, $full, $inherit, $prop, $allow)

    function Unlock-YaroKey([string]$SubPath) {
      $needsGrant = $true
      $probe = $null
      try {
        $probe = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($SubPath, $false)
        if ($null -eq $probe) { return }
        $sd = $probe.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access)
        foreach ($r in $sd.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])) {
          if ($r.IdentityReference -eq $adminSid -and $r.AccessControlType -eq $allow -and (($r.RegistryRights -band $full) -eq $full)) {
            $needsGrant = $false
            break
          }
        }
      } catch [System.Security.SecurityException] {
        $needsGrant = $true
      } finally {
        if ($probe) { $probe.Close() }
      }
      if (-not $needsGrant) { return }

      $kOwn = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
        $SubPath,
        [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
        [System.Security.AccessControl.RegistryRights]::TakeOwnership
      )
      if ($null -eq $kOwn) { return }
      try {
        $ownAcl = $kOwn.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Owner)
        $ownAcl.SetOwner($adminSid)
        $kOwn.SetAccessControl($ownAcl)
      } finally {
        $kOwn.Close()
      }

      $kPerm = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey(
        $SubPath,
        [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree,
        ([System.Security.AccessControl.RegistryRights]::ReadPermissions -bor [System.Security.AccessControl.RegistryRights]::ChangePermissions)
      )
      if ($null -eq $kPerm) { return }
      try {
        $permAcl = $kPerm.GetAccessControl([System.Security.AccessControl.AccessControlSections]::Access)
        $permAcl.SetAccessRule($fullRule)
        $kPerm.SetAccessControl($permAcl)
        "  [i] Выданы права Администратора: HKLM\$SubPath"
      } finally {
        $kPerm.Close()
      }
    }

    $svcs = @($env:YARO_SERVICES -split '\s+' | Where-Object { $_ })
    foreach ($s in $svcs) {
      Unlock-YaroKey "YARO_SYS\ControlSet001\Services\$s"
    }
    foreach ($softPath in @(
      'YARO_SOFT\Microsoft\Windows Defender',
      'YARO_SOFT\Microsoft\Windows Defender\Features',
      'YARO_SOFT\Microsoft\Windows Defender\UX Configuration',
      'YARO_SOFT\Policies\Microsoft\Windows Defender',
      'YARO_SOFT\Policies\Microsoft\Windows Defender\Real-Time Protection',
      'YARO_SOFT\Policies\Microsoft\Windows Defender\Spynet',
      'YARO_SOFT\Policies\Microsoft\Windows Defender Security Center'
    )) {
      Unlock-YaroKey $softPath
    }

    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
    return
  }
}
