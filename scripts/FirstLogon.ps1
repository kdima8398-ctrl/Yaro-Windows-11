# =============================================================================
#  Yaro - settings of the signed-in user and power plan (part 2 of 2)
#  Runs at the first sign-in after Windows Setup, or via Yaro-Apply.cmd.
#  Clean install log: %SystemRoot%\Setup\Scripts\Yaro\FirstLogon.log
#  Installed Windows: %LOCALAPPDATA%\Yaro\FirstLogon.log
# =============================================================================
param([switch]$Setup)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'YaroCommon.ps1')
$ErrorActionPreference = 'Continue'
$LogDir = if ($Setup) { $YaroLogDir } else { Join-Path $env:LOCALAPPDATA 'Yaro' }
New-Item -ItemType Directory -Force -Path $LogDir -ErrorAction Stop | Out-Null
Start-Transcript -Path (Join-Path $LogDir 'FirstLogon.log') -Append -ErrorAction Stop | Out-Null
"Yaro FirstLogon.ps1 started $(Get-Date) as $env:USERNAME"

"== Current user settings"
Set-YaroRegistryValue "HKCU\Control Panel\Desktop" 'MenuShowDelay' '0' 'REG_SZ'
Set-YaroRegistryValue "HKCU\Control Panel\Desktop" 'AutoEndTasks' '0' 'REG_SZ'
Set-YaroRegistryValue "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings" 'TaskbarEndTask' '1' 'REG_DWORD'
Set-YaroGraphicsDefaults 'HKCU'
Set-YaroRegistryValue "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" 'AppsUseLightTheme' '0' 'REG_DWORD'
Set-YaroRegistryValue "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" 'SystemUsesLightTheme' '0' 'REG_DWORD'
Set-YaroRegistryValue "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" 'SeparateProcess' '1' 'REG_DWORD'
Set-YaroRegistryValue "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" 'TaskbarMn' '0' 'REG_DWORD'
Set-YaroRegistryValue "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" 'ShowTaskViewButton' '0' 'REG_DWORD'
Set-YaroRegistryValue "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" 'ShowCopilotButton' '0' 'REG_DWORD'
Set-YaroRegistryValue "HKCU\Software\Microsoft\Windows\CurrentVersion\Search" 'SearchboxTaskbarMode' '0' 'REG_DWORD'
Set-YaroRegistryValue "HKCU\Software\Microsoft\Windows\CurrentVersion\Search" 'BingSearchEnabled' '0' 'REG_DWORD'
if ($Setup) { Set-YaroUserPolicies 'HKCU' }
Set-YaroRegistryValue "HKCU\Software\Microsoft\Windows\CurrentVersion\WinTrust\Trust Providers\Software Publishing" 'State' '0x00023c00' 'REG_DWORD'
Set-YaroRegistryValue "HKCU\System\GameConfigStore" 'GameDVR_Enabled' '0' 'REG_DWORD'
Set-YaroRegistryValue "HKCU\Software\Microsoft\Windows\CurrentVersion\GameDVR" 'HistoricalCaptureEnabled' '0' 'REG_DWORD'
if ($ArgonPerformance) { Set-YaroRegistryValue "HKCU\Software\Microsoft\GameBar" 'AutoGameModeEnabled' '0' 'REG_DWORD' }
Set-YaroRegistryValue "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" 'ContentDeliveryAllowed' '0' 'REG_DWORD'
Set-YaroRegistryValue "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" 'OemPreInstalledAppsEnabled' '0' 'REG_DWORD'
Set-YaroRegistryValue "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" 'PreInstalledAppsEnabled' '0' 'REG_DWORD'
Set-YaroRegistryValue "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" 'PreInstalledAppsEverEnabled' '0' 'REG_DWORD'
Set-YaroRegistryValue "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" 'SilentInstalledAppsEnabled' '0' 'REG_DWORD'
Set-YaroRegistryValue "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" 'SoftLandingEnabled' '0' 'REG_DWORD'
Set-YaroRegistryValue "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" 'SystemPaneSuggestionsEnabled' '0' 'REG_DWORD'
Set-YaroRegistryValue "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" 'SubscribedContent-310093Enabled' '0' 'REG_DWORD'
Set-YaroRegistryValue "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" 'SubscribedContent-338388Enabled' '0' 'REG_DWORD'
Set-YaroRegistryValue "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" 'SubscribedContent-338389Enabled' '0' 'REG_DWORD'
Set-YaroRegistryValue "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" 'SubscribedContent-338393Enabled' '0' 'REG_DWORD'
Set-YaroRegistryValue "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" 'SubscribedContent-353694Enabled' '0' 'REG_DWORD'
Set-YaroRegistryValue "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" 'SubscribedContent-353696Enabled' '0' 'REG_DWORD'
# Windows 10 style context menu
try {
  $k = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32')
  $k.SetValue('', ''); $k.Close()
} catch { Write-YaroFailure "classic context menu: $($_.Exception.Message)" }
# Folders: do not guess folder type (faster Explorer)
Set-YaroRegistryValue 'HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell' 'FolderType' 'NotSpecified' 'REG_SZ'

if ($Setup) { Set-YaroMachinePerformance }

Remove-YaroOneDriveStartup 'HKCU'

"== Leftover apps of the current user"
$apps = 'Microsoft.Windows.DevHome', 'MicrosoftWindows.CrossDevice', 'Microsoft.Edge.GameAssist', 'AppUp.IntelGraphicsControlPanel',
        'Microsoft.Copilot', 'Microsoft.BingSearch', 'MicrosoftWindows.Client.WebExperience', 'Microsoft.OutlookForWindows'
$installedApps = $null
try { $installedApps = @(Get-AppxPackage -ErrorAction Stop | Where-Object { $_.Name -in $apps }) }
catch { "  WARN app inventory unavailable; querying packages by name" }
foreach ($a in $apps) {
  $packages = if ($null -eq $installedApps) {
    try { Get-AppxPackage -Name $a -ErrorAction Stop }
    catch { Write-YaroFailure "query app $a - $($_.Exception.Message)" | Out-Host }
  } else {
    $installedApps.Where({ $_.Name -eq $a })
  }
  foreach ($package in $packages) {
    try { Remove-AppxPackage -Package $package.PackageFullName -ErrorAction Stop }
    catch { Write-YaroFailure "remove $($package.Name): $($_.Exception.Message)" }
  }
}

"== Wallpaper"
$Sw = Join-Path $PSScriptRoot 'SetWallpaper.ps1'
if (-not $SetWallpaper) {
  "  skipped (Yaro wallpaper is off)"
} elseif ((Test-Path -LiteralPath $Sw) -and (Test-Path -LiteralPath $YaroWallpaperPath)) {
  try { & $Sw -Once:$Setup } catch { Write-YaroFailure "wallpaper: $($_.Exception.Message)" }
} else {
  Write-YaroFailure 'wallpaper script or image not found'
}

"Yaro FirstLogon.ps1 finished $(Get-Date)"
Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
if (-not $Setup -and $script:YaroFailures) { exit 2 }
