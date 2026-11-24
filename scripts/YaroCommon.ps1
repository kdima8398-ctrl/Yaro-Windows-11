# Shared settings and registry helpers for both Yaro stages.
# ---------------------------- Yaro options -----------------------------------
# $true applies the Yaro setting; $false skips it on this run.
$DisableDefender    = $true   # Microsoft Defender antivirus OFF (no built-in malware protection!)
$DisableSmartScreen = $true   # SmartScreen OFF
$SilentUAC          = $true   # admin programs elevate WITHOUT a confirmation window
$PauseUpdates       = $true   # Windows Update: no automatic installs, paused until 2077
$DisablePrinting    = $true   # print spooler OFF (printers will not work)
$DisableBtHandsFree = $true   # Bluetooth headset mic OFF (headphones stay in stereo in games)
$DisableVPN         = $true   # RasMan/RasAuto OFF (built-in Windows VPN will not work)
$SetWallpaper       = $true   # Yaro notebook wallpaper on the desktop of every user
$ArgonPerformance   = $true   # Argon tweaks: Ultimate Performance plan + min CPU 5%, Game Mode on,
                              #   SystemResponsiveness 10 (lowest value Windows accepts), no 8.3 names.
                              #   Power throttling stays with Windows: background apps get less power, so the
                              #   game keeps more turbo headroom and 12-14th gen Intel can use its E-cores.
                              #   Laptop battery lasts less.
$DisableWindowsAI   = $true   # Remove Copilot / CoreAI, disable Recall feature and Notepad AI
$DebloatEdge        = $true   # Disable Edge sidebar, shopping, rewards, recommendations and telemetry
$RemoveOneDrive     = $true   # Uninstall OneDriveSetup + disable OneSyncSvc (also keeps sync policy off)
$EnablePhotoViewer  = $true   # Register classic Windows Photo Viewer for .jpg/.png/.bmp/.gif/.ico
$DisableBgApps      = $true   # Prevent Microsoft Store apps from running in the background
$PreferIPv4         = $true   # Prefer IPv4 over IPv6 (DisabledComponents = 32) without disabling IPv6
$DisableSearchIndex = $false  # Windows Search service (WSearch) OFF (enable if using Everything/etc.)
$DisableHibernation = $false  # Full hibernation OFF (powercfg /h off; Fast Startup is always disabled)
$RemoveIntelApp     = $false  # Remove Intel Graphics Command Center (AppUp.IntelGraphicsExperience + igccservice)
$ForceMSI           = $false  # Argon MSI interrupts for GPU, NVMe and network (an unsuitable driver can break)
# -----------------------------------------------------------------------------

$YaroLogDir = Join-Path $env:SystemRoot 'Setup\Scripts\Yaro'
$YaroWallpaperPath = Join-Path $env:SystemRoot 'Web\Wallpaper\Yaro\yaro-wallpaper.png'
$script:YaroFailures = 0

function Write-YaroFailure([string]$Message) {
  $script:YaroFailures++
  "  FAIL $Message"
}

function Get-YaroRegistryPath([string]$Key) {
  $hive, $subkey = $Key -split '\\', 2
  switch ($hive) {
    'HKLM' { "HKEY_LOCAL_MACHINE\$subkey" }
    'HKCU' { "HKEY_CURRENT_USER\$subkey" }
    'HKU' { "HKEY_USERS\$subkey" }
    default { throw "Unsupported registry path: $Key" }
  }
}

function Set-YaroRegistryValue([string]$Key, [string]$Name, [string]$Data, [ValidateSet('REG_DWORD', 'REG_SZ')][string]$Type = 'REG_DWORD') {
  try {
    $value = $Data
    $kind = [Microsoft.Win32.RegistryValueKind]::String
    if ($Type -eq 'REG_DWORD') {
      $kind = [Microsoft.Win32.RegistryValueKind]::DWord
      if ($Data.StartsWith('0x', [StringComparison]::OrdinalIgnoreCase)) {
        $value = [Convert]::ToInt32($Data.Substring(2), 16)
      } else {
        $value = [Convert]::ToInt32($Data, 10)
      }
    }
    [Microsoft.Win32.Registry]::SetValue((Get-YaroRegistryPath $Key), $Name, $value, $kind)
  } catch {
    Write-YaroFailure "$Key\$Name - $($_.Exception.Message)"
  }
}

function Remove-YaroRegistryValue([string]$Key, [string]$Name) {
  try {
    $regPath = 'Registry::' + (Get-YaroRegistryPath $Key)
    if (Test-Path -LiteralPath $regPath -ErrorAction SilentlyContinue) {
      Remove-ItemProperty -LiteralPath $regPath -Name $Name -ErrorAction SilentlyContinue
    }
  } catch {
    Write-YaroFailure "remove $Key\$Name - $($_.Exception.Message)"
  }
}

# C:\Windows\Temp must keep its own permissions: users may create files there, inheritance is off.
# Cleaners that delete and recreate the folder make it inherit C:\Windows (users: read only),
# and then installers fail at ~90% with Windows Installer errors 2503 / 2502.
function Test-YaroTempAcl([string]$Path) {
  $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
  if (-not $acl.AreAccessRulesProtected) { return $false }
  $users = [Security.Principal.SecurityIdentifier]'S-1-5-32-545'
  $createFiles = [Security.AccessControl.FileSystemRights]::CreateFiles
  foreach ($rule in $acl.Access) {
    if ($rule.AccessControlType -ne 'Allow') { continue }
    try { $sid = $rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]) } catch { continue }
    if ($sid -eq $users -and ($rule.FileSystemRights -band $createFiles) -eq $createFiles) { return $true }
  }
  return $false
}

function Repair-YaroWindowsTemp([string]$Path = (Join-Path $env:SystemRoot 'Temp')) {
  try {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return }
    if (Test-YaroTempAcl $Path) { "  permissions ok"; return }
    # Windows defaults: CREATOR OWNER, SYSTEM and Administrators full control; Users may create files and folders
    $out = & icacls.exe $Path /inheritance:r /grant:r '*S-1-3-0:(OI)(CI)(IO)(F)' '*S-1-5-18:(OI)(CI)(F)' '*S-1-5-32-544:(OI)(CI)(F)' '*S-1-5-32-545:(CI)(S,WD,AD,X)' 2>&1
    if ($LASTEXITCODE -eq 0 -and (Test-YaroTempAcl $Path)) {
      "  repaired: default permissions restored (installer errors 2503/2502)"
    } else {
      Write-YaroFailure "repair permissions of $Path (icacls exit $LASTEXITCODE): $(($out | Out-String).Trim())"
    }
  } catch {
    Write-YaroFailure "check permissions of $Path - $($_.Exception.Message)"
  }
}

function Clear-YaroUserServiceTemplate([string]$Name) {
  $subkey = "SYSTEM\CurrentControlSet\Services\$Name"
  $props = Get-ItemProperty -LiteralPath "HKLM:\$subkey" -ErrorAction SilentlyContinue
  if ($props -and $props.Start -eq 4 -and $props.UserServiceFlags -eq 3) {
    Set-YaroRegistryValue "HKLM\$subkey" 'UserServiceFlags' '0'
  }
}

function Merge-YaroGraphicsDefaults([string]$Settings) {
  foreach ($name in 'SwapEffectUpgradeEnable', 'VRROptimizeEnable') {
    if ($Settings -match "(?:^|;)\s*$name\s*=") { continue }
    if ($Settings -and -not $Settings.EndsWith(';')) { $Settings += ';' }
    $Settings += "$name=1;"
  }
  $Settings
}

function Set-YaroGraphicsDefaults([string]$UserHive) {
  $key = "$UserHive\Software\Microsoft\DirectX\UserGpuPreferences"
  $name = 'DirectXUserGlobalSettings'
  try {
    $current = [Microsoft.Win32.Registry]::GetValue((Get-YaroRegistryPath $key), $name, '')
    if ($null -ne $current -and $current -isnot [string]) {
      "  WARN unexpected registry value type for $name"
      return
    }
    $updated = Merge-YaroGraphicsDefaults $current
    if ($updated -cne $current) { Set-YaroRegistryValue $key $name $updated 'REG_SZ' }
  } catch {
    Write-YaroFailure "graphics preferences: $($_.Exception.Message)"
  }
}

function Set-YaroAcPerformanceMode {
  $activeScheme = & powercfg.exe /getactivescheme 2>$null
  if ($LASTEXITCODE -ne 0 -or "$activeScheme" -notmatch '\b[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\b') {
    return $false
  }
  $scheme = [guid]$Matches[0]
  try {
    if (-not ('Yaro.PowerMode' -as [type])) {
      Add-Type -Namespace Yaro -Name PowerMode -ErrorAction Stop -MemberDefinition @'
[DllImport("powrprof.dll", ExactSpelling = true)]
public static extern uint PowerReadACValueIndex(IntPtr root, ref Guid scheme, ref Guid subgroup, ref Guid setting, out uint index);
[DllImport("powrprof.dll", ExactSpelling = true)]
public static extern uint PowerSetUserConfiguredACPowerMode(ref Guid mode);
'@
    }

    # The power-mode selector applies only to Balanced and plans derived from it.
    $noSubgroup = [guid]'fea3413e-7e05-4911-9a71-700331f1c294'
    $personalitySetting = [guid]'245d8541-3943-4422-b025-13a784f679b7'
    $personality = [uint32]0
    $status = [Yaro.PowerMode]::PowerReadACValueIndex([IntPtr]::Zero, [ref]$scheme, [ref]$noSubgroup, [ref]$personalitySetting, [ref]$personality)
    if ($status -ne 0 -or $personality -ne 2) { return $false } # 2 = Balanced

    $bestPerformance = [guid]'ded574b5-45a0-4f42-8737-46345c09c238'
    $status = [Yaro.PowerMode]::PowerSetUserConfiguredACPowerMode([ref]$bestPerformance)
    if ($status -eq 0) { return $true }
    Write-Warning "Could not set Best Performance on AC (Windows error $status)"
  } catch {
    Write-Warning "Could not set Best Performance on AC: $($_.Exception.Message)"
  }
  return $false
}

function Set-YaroMachinePerformance {
  # Argon keeps Ultimate Performance on AC and battery; otherwise prefer the Balanced power mode.
  if (-not $ArgonPerformance -and (Set-YaroAcPerformanceMode)) {
    "== Power mode: Best Performance when plugged in"
  } else {
    "== Power plan: Ultimate Performance, minimum CPU state 5%"
    $scheme = 'e9a42b02-d5df-448d-aa00-03f14749eb62'
    # powercfg /list does not fail for a missing plan, so nothing red ends up in the log
    $schemeAvailable = [bool]((& powercfg.exe /list 2>$null) -match $scheme)
    if (-not $schemeAvailable) {
      & powercfg.exe /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 $scheme *> $null
      $schemeAvailable = $LASTEXITCODE -eq 0
    }
    if ($schemeAvailable) {
      $configured = $true
      foreach ($command in '/setacvalueindex', '/setdcvalueindex') {
        & powercfg.exe $command $scheme SUB_PROCESSOR PROCTHROTTLEMIN 5 *> $null
        if ($LASTEXITCODE -ne 0) {
          $configured = $false
          Write-YaroFailure "powercfg $command (exit $LASTEXITCODE)"
        }
      }
      if ($configured) {
        & powercfg.exe /setactive $scheme *> $null
        if ($LASTEXITCODE -ne 0) { Write-YaroFailure "power plan activation (exit $LASTEXITCODE)" }
      }
    } else {
      Write-YaroFailure 'Ultimate Performance plan unavailable'
    }
  }

  "== Memory compression"
  try { Enable-MMAgent -MemoryCompression -ErrorAction Stop }
  catch { Write-YaroFailure "memory compression: $($_.Exception.Message)" }
}

function Test-YaroOneDriveInactive {
  $sync = [Microsoft.Win32.Registry]::GetValue('HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\OneDrive', 'DisableFileSyncNGSC', $null)
  $reports = [Microsoft.Win32.Registry]::GetValue('HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\OneDrive', 'EnableSyncAdminReports', $null)
  return ($sync -eq 1 -and $reports -ne 1)
}

function Remove-YaroOneDriveStartup([string]$UserHive) {
  try {
    if (-not (Test-YaroOneDriveInactive)) { return }
    $policy = Get-YaroRegistryPath "$UserHive\Software\Policies\Microsoft\OneDrive"
    if ([Microsoft.Win32.Registry]::GetValue($policy, 'EnableAutoStart', $null) -eq 1) { return }

    $run = Get-YaroRegistryPath "$UserHive\Software\Microsoft\Windows\CurrentVersion\Run"
    $entries = @{ OneDriveSetup = @("$env:SystemRoot\System32\OneDriveSetup.exe") }
    if ($UserHive -eq 'HKCU') {
      $entries['OneDrive'] = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive\OneDrive.exe')
        foreach ($dir in $env:ProgramFiles, [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')) {
          if ($dir) { Join-Path $dir 'Microsoft OneDrive\OneDrive.exe' }
        }
      )
    }
    foreach ($name in $entries.Keys) {
      $command = [Microsoft.Win32.Registry]::GetValue($run, $name, $null)
      if ($command -isnot [string]) { continue }
      $command = [Environment]::ExpandEnvironmentVariables($command).Trim()
      $argument = if ($name -eq 'OneDriveSetup') { '/thfirstsetup' } else { '/background' }
      foreach ($exe in $entries[$name]) {
        if ($command -in "$exe $argument", ('"{0}" {1}' -f $exe, $argument)) {
          Remove-ItemProperty -LiteralPath "Registry::$run" -Name $name -ErrorAction Stop
          "  removed $name startup (OneDrive sync is blocked)"
          break
        }
      }
    }
  } catch { Write-YaroFailure "OneDrive startup ($UserHive): $($_.Exception.Message)" }
}

function Uninstall-YaroOneDrive {
  if (-not $RemoveOneDrive) { return }
  "== OneDrive uninstall"
  try {
    Get-Process -Name 'OneDrive', 'FileCoAuth' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    $candidates = @(
      (Join-Path $env:SystemRoot 'System32\OneDriveSetup.exe'),
      (Join-Path $env:SystemRoot 'SysWOW64\OneDriveSetup.exe')
    )
    $ran = $false
    foreach ($setupExe in $candidates) {
      if (Test-Path -LiteralPath $setupExe -PathType Leaf) {
        Start-Process -FilePath $setupExe -ArgumentList '/uninstall' -Wait -WindowStyle Hidden -ErrorAction Stop
        "  ran $setupExe /uninstall"
        $ran = $true
        break
      }
    }
    if (-not $ran) { "  OneDriveSetup.exe not found (already removed)" }

    foreach ($leftover in (Join-Path $env:LOCALAPPDATA 'Microsoft\OneDrive'), (Join-Path $env:ProgramData 'Microsoft OneDrive')) {
      if (Test-Path -LiteralPath $leftover) {
        Remove-Item -LiteralPath $leftover -Recurse -Force -ErrorAction SilentlyContinue
      }
    }
    $userFolder = $env:OneDrive
    if (-not [string]::IsNullOrWhiteSpace($userFolder) -and (Test-Path -LiteralPath $userFolder -PathType Container)) {
      if (-not (Get-ChildItem -LiteralPath $userFolder -Force -ErrorAction SilentlyContinue)) {
        Remove-Item -LiteralPath $userFolder -Force -ErrorAction SilentlyContinue
        [Environment]::SetEnvironmentVariable('OneDrive', $null, 'User')
      }
    }
  } catch {
    Write-YaroFailure "OneDrive uninstall: $($_.Exception.Message)"
  }
}

function Remove-YaroCoreAI([string]$UserSidValue) {
  if (-not $DisableWindowsAI) { return }
  try {
    $packages = @(Get-AppxPackage -Name 'MicrosoftWindows.Client.CoreAI' -ErrorAction SilentlyContinue)
    if (-not $packages) { return }
    foreach ($pkg in $packages) {
      if ($UserSidValue) {
        $eol = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\EndOfLife\$UserSidValue\$($pkg.PackageFullName)"
        if (-not (Test-Path -LiteralPath $eol)) {
          New-Item -Path $eol -Force -ErrorAction SilentlyContinue | Out-Null
        }
      }
      try {
        Remove-AppxPackage -Package $pkg.PackageFullName -ErrorAction Stop
        "  removed $($pkg.Name)"
      } catch {
        "  NOTE CoreAI protected on this Windows build ($($_.Exception.Message))"
      }
    }
  } catch {
    "  WARN CoreAI cleanup: $($_.Exception.Message)"
  }
}

function Set-YaroUserPolicies([string]$UserHive) {
  Set-YaroRegistryValue "$UserHive\Software\Policies\Microsoft\Windows\Explorer" 'DisableSearchBoxSuggestions' '1' 'REG_DWORD'
  if ($DisableWindowsAI) {
    Set-YaroRegistryValue "$UserHive\Software\Policies\Microsoft\Windows\WindowsCopilot" 'TurnOffWindowsCopilot' '1' 'REG_DWORD'
  }
}

function Set-YaroUserSettings([string]$UserHive) {
  Set-YaroRegistryValue "$UserHive\Control Panel\Desktop" 'MenuShowDelay' '0' 'REG_SZ'
  Set-YaroRegistryValue "$UserHive\Control Panel\Desktop" 'AutoEndTasks' '0' 'REG_SZ'
  Set-YaroRegistryValue "$UserHive\Control Panel\Accessibility\StickyKeys" 'Flags' '506' 'REG_SZ'
  Set-YaroRegistryValue "$UserHive\Control Panel\UnsupportedHardwareNotificationCache" 'SV1' '0' 'REG_DWORD'
  Set-YaroRegistryValue "$UserHive\Control Panel\UnsupportedHardwareNotificationCache" 'SV2' '0' 'REG_DWORD'

  Set-YaroRegistryValue "$UserHive\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings" 'TaskbarEndTask' '1' 'REG_DWORD'
  Set-YaroGraphicsDefaults $UserHive
  Set-YaroRegistryValue "$UserHive\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" 'AppsUseLightTheme' '0' 'REG_DWORD'
  Set-YaroRegistryValue "$UserHive\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" 'SystemUsesLightTheme' '0' 'REG_DWORD'

  $adv = "$UserHive\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
  Set-YaroRegistryValue $adv 'SeparateProcess' '1' 'REG_DWORD'
  Set-YaroRegistryValue $adv 'TaskbarMn' '0' 'REG_DWORD'
  Set-YaroRegistryValue $adv 'ShowTaskViewButton' '0' 'REG_DWORD'
  Set-YaroRegistryValue $adv 'ShowCopilotButton' '0' 'REG_DWORD'
  Set-YaroRegistryValue $adv 'LaunchTo' '1' 'REG_DWORD'
  Set-YaroRegistryValue $adv 'HideFileExt' '0' 'REG_DWORD'
  Set-YaroRegistryValue $adv 'Start_TrackProgs' '0' 'REG_DWORD'
  # Start and Explorer: no recommendations, account nags or sync-provider ads (nothing fetched for them)
  Set-YaroRegistryValue $adv 'Start_IrisRecommendations' '0' 'REG_DWORD'
  Set-YaroRegistryValue $adv 'Start_AccountNotifications' '0' 'REG_DWORD'
  Set-YaroRegistryValue $adv 'ShowSyncProviderNotifications' '0' 'REG_DWORD'
  Set-YaroRegistryValue "$UserHive\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize" 'StartupDelayInMSec' '0' 'REG_DWORD'

  Set-YaroRegistryValue "$UserHive\Software\Microsoft\Windows\CurrentVersion\Search" 'SearchboxTaskbarMode' '0' 'REG_DWORD'
  Set-YaroRegistryValue "$UserHive\Software\Microsoft\Windows\CurrentVersion\Search" 'BingSearchEnabled' '0' 'REG_DWORD'
  Set-YaroRegistryValue "$UserHive\Software\Microsoft\Windows\CurrentVersion\WinTrust\Trust Providers\Software Publishing" 'State' '0x00023c00' 'REG_DWORD'

  if ($UserHive -eq 'HKCU') {
    # Explorer: hide Home and Gallery from navigation pane
    Set-YaroRegistryValue "$UserHive\Software\Classes\CLSID\{f874310e-b6b7-47dc-bc84-b9e6b38f5903}" 'System.IsPinnedToNameSpaceTree' '0' 'REG_DWORD'
    Set-YaroRegistryValue "$UserHive\Software\Classes\CLSID\{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}" 'System.IsPinnedToNameSpaceTree' '0' 'REG_DWORD'

    # Windows 10 style context menu (classic CLSID + newer Windows 11 build fallback)
    foreach ($clsid in '{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}', '{51668040-5e31-4023-bbe3-149163bd80f1}') {
      Set-YaroRegistryValue "$UserHive\Software\Classes\CLSID\$clsid\InprocServer32" '' '' 'REG_SZ'
    }

    # Folders: do not guess folder type (faster Explorer)
    Set-YaroRegistryValue "$UserHive\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell" 'FolderType' 'NotSpecified' 'REG_SZ'
  }

  # Game DVR & Mode
  Set-YaroRegistryValue "$UserHive\System\GameConfigStore" 'GameDVR_Enabled' '0' 'REG_DWORD'
  Set-YaroRegistryValue "$UserHive\Software\Microsoft\Windows\CurrentVersion\GameDVR" 'HistoricalCaptureEnabled' '0' 'REG_DWORD'
  # Game Mode on: Windows prioritises the game and holds back updates and notifications while it runs
  if ($ArgonPerformance) { Set-YaroRegistryValue "$UserHive\Software\Microsoft\GameBar" 'AutoGameModeEnabled' '1' 'REG_DWORD' }

  # Privacy: advertising ID, tailored experiences, input telemetry, feedback prompts
  Set-YaroRegistryValue "$UserHive\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" 'Enabled' '0' 'REG_DWORD'
  # Do not hand the Windows language list to websites and apps (Settings > Privacy > General)
  Set-YaroRegistryValue "$UserHive\Control Panel\International\User Profile" 'HttpAcceptLanguageOptOut' '1' 'REG_DWORD'
  Set-YaroRegistryValue "$UserHive\Software\Microsoft\Windows\CurrentVersion\Privacy" 'TailoredExperiencesWithDiagnosticDataEnabled' '0' 'REG_DWORD'
  Set-YaroRegistryValue "$UserHive\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy" 'HasAccepted' '0' 'REG_DWORD'
  Set-YaroRegistryValue "$UserHive\Software\Microsoft\Input\TIPC" 'Enabled' '0' 'REG_DWORD'
  Set-YaroRegistryValue "$UserHive\Software\Microsoft\InputPersonalization" 'RestrictImplicitInkCollection' '1' 'REG_DWORD'
  Set-YaroRegistryValue "$UserHive\Software\Microsoft\InputPersonalization" 'RestrictImplicitTextCollection' '1' 'REG_DWORD'
  Set-YaroRegistryValue "$UserHive\Software\Microsoft\InputPersonalization\TrainedDataStore" 'HarvestContacts' '0' 'REG_DWORD'
  Set-YaroRegistryValue "$UserHive\Software\Microsoft\Personalization\Settings" 'AcceptedPrivacyPolicy' '0' 'REG_DWORD'
  Set-YaroRegistryValue "$UserHive\Software\Microsoft\Siuf\Rules" 'NumberOfSIUFInPeriod' '0' 'REG_DWORD'
  Remove-YaroRegistryValue "$UserHive\Software\Microsoft\Siuf\Rules" 'PeriodInNanoSeconds'
  Set-YaroRegistryValue "$UserHive\Software\Microsoft\Input\Settings" 'InsightsEnabled' '0' 'REG_DWORD'

  # Fewer background notifications: "Suggested" toasts and account notifications in Settings
  Set-YaroRegistryValue "$UserHive\Software\Microsoft\Windows\CurrentVersion\Notifications\Settings\Windows.SystemToast.Suggested" 'Enabled' '0' 'REG_DWORD'
  Set-YaroRegistryValue "$UserHive\Software\Microsoft\Windows\CurrentVersion\SystemSettings\AccountNotifications" 'EnableAccountNotifications' '0' 'REG_DWORD'

  if ($DisableBgApps) {
    Set-YaroRegistryValue "$UserHive\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" 'GlobalUserDisabled' '1' 'REG_DWORD'
  }

  # Cloud content / suggestions / silent app installs
  $cdm = "$UserHive\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
  foreach ($val in 'ContentDeliveryAllowed', 'OemPreInstalledAppsEnabled', 'PreInstalledAppsEnabled',
                   'PreInstalledAppsEverEnabled', 'SilentInstalledAppsEnabled', 'SoftLandingEnabled',
                   'SystemPaneSuggestionsEnabled', 'FeatureManagementEnabled', 'SubscribedContentEnabled',
                   'SubscribedContent-310093Enabled', 'SubscribedContent-338387Enabled', 'SubscribedContent-338388Enabled',
                   'SubscribedContent-338389Enabled', 'SubscribedContent-338393Enabled',
                   'SubscribedContent-353694Enabled', 'SubscribedContent-353696Enabled') {
    Set-YaroRegistryValue $cdm $val '0' 'REG_DWORD'
  }
}
