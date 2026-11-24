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
# On live runs, flush previously guessed Explorer folder views before enforcing NotSpecified.
if (-not $Setup) {
  foreach ($bagKey in 'Bags', 'BagMRU') {
    $bagPath = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\$bagKey"
    if (Test-Path -LiteralPath $bagPath) {
      Remove-Item -LiteralPath $bagPath -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}
Set-YaroUserSettings 'HKCU'
if ($Setup) {
  Set-YaroUserPolicies 'HKCU'
  Set-YaroMachinePerformance
  $currentSid = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
  Remove-YaroCoreAI $currentSid
}

Remove-YaroOneDriveStartup 'HKCU'
Uninstall-YaroOneDrive

"== Leftover apps of the current user"
$apps = 'Microsoft.Windows.DevHome', 'MicrosoftWindows.CrossDevice', 'Microsoft.Edge.GameAssist', 'AppUp.IntelGraphicsControlPanel',
        'Microsoft.Copilot', 'Microsoft.BingSearch', 'MicrosoftWindows.Client.WebExperience', 'Microsoft.OutlookForWindows'
if ($RemoveIntelApp) { $apps += 'AppUp.IntelGraphicsExperience' }
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
