# =============================================================================
#  Yaro - system-wide settings (part 1 of 2)
#  Runs as SYSTEM during Windows Setup (specialize pass), or as Administrator
#  on an already installed Windows via Yaro-Apply.cmd.
#  Log: %SystemRoot%\Setup\Scripts\Yaro\Specialize.log
# =============================================================================
param([switch]$Live, [Security.Principal.SecurityIdentifier]$UserSid)

$ErrorActionPreference = 'Stop'
if ($Live) {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    if ($UserSid) { throw 'The system stage requires administrative rights.' }
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Live -UserSid {1}' -f $PSCommandPath, $identity.User.Value
    $child = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $arguments -Verb RunAs -Wait -PassThru -ErrorAction Stop
    exit $child.ExitCode
  }
  if (-not $UserSid) { $UserSid = $identity.User }
}

. (Join-Path $PSScriptRoot 'YaroCommon.ps1')
$ErrorActionPreference = 'Continue'
function Svc([string]$Name, [int]$Start) {
  $subkey = "SYSTEM\CurrentControlSet\Services\$Name"
  if (-not (Test-Path -LiteralPath "HKLM:\$subkey" -ErrorAction SilentlyContinue)) { return }
  if ((Get-ItemProperty -LiteralPath "HKLM:\$subkey" -Name Start -ErrorAction SilentlyContinue).Start -eq $Start) { return }
  try {
    [Microsoft.Win32.Registry]::SetValue("HKEY_LOCAL_MACHINE\$subkey", 'Start', $Start, [Microsoft.Win32.RegistryValueKind]::DWord)
    return
  } catch { $why = $_.Exception.Message }
  # Some service keys are writable only by SYSTEM; the Service Control Manager accepts administrators.
  $mode = @('boot', 'system', 'auto', 'demand', 'disabled')[$Start]
  $out = & sc.exe config $Name start= $mode 2>&1
  if ($LASTEXITCODE -ne 0) { Write-YaroFailure "$Name start=$mode - $why sc.exe: $(($out | Out-String).Trim())" }
}
function Test-YaroOneDriveReportingTask($Task) {
  if ($Task.TaskPath -ne '\' -or $Task.TaskName -notlike 'OneDrive Reporting Task-S-1-*') { return $false }
  $actions = @($Task.Actions)
  if ($actions.Count -ne 1 -or $actions[0].Arguments -ne '/reporting') { return $false }
  $path = ([string]$actions[0].Execute).Trim('"')
  return ($path -like '*\Microsoft\OneDrive\OneDriveStandaloneUpdater.exe' -or
          $path -like '*\Microsoft OneDrive\OneDriveStandaloneUpdater.exe')
}
$LogDir = $YaroLogDir
New-Item -ItemType Directory -Force -Path $LogDir -ErrorAction Stop | Out-Null
Start-Transcript -Path (Join-Path $LogDir 'Specialize.log') -Append -ErrorAction Stop | Out-Null
"Yaro Specialize.ps1 started $(Get-Date)  Live=$Live"

if ($Live) {
  try {
    Checkpoint-Computer -Description 'Before Yaro' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
    "  restore point created"
  } catch {
    Write-YaroFailure "restore point not created - $($_.Exception.Message)"
    "  Usually System Protection is off. To turn it on: Win+R > SystemPropertiesProtection >"
    "  drive C: > Configure > Turn on system protection > OK, then run Yaro-Apply.cmd again."
    $answer = Read-Host '  Continue WITHOUT a restore point? [y/N]'
    if ($answer -notmatch '^\s*y(es)?\s*$') {
      "  Stopped. Nothing was changed."
      Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
      exit 1
    }
  }
}

# ---------- 1. Store apps (removed for all users) ----------
"== Apps"
$Apps = @(
  'Microsoft.GamingApp', 'Microsoft.XboxGamingOverlay', 'Microsoft.XboxSpeechToTextOverlay',
  'Microsoft.BingSearch', 'Microsoft.Copilot', 'Microsoft.Windows.Ai.Copilot.Provider',
  'Microsoft.WidgetsPlatformRuntime', 'MicrosoftWindows.Client.WebExperience',
  'Microsoft.WindowsMaps', 'Microsoft.MicrosoftStickyNotes', 'MicrosoftCorporationII.MicrosoftFamily',
  'Microsoft.ZuneVideo', 'Microsoft.WindowsCamera', 'Microsoft.ApplicationCompatibilityEnhancements',
  'Microsoft.WindowsAlarms', 'Microsoft.Getstarted', 'Microsoft.YourPhone', 'MSTeams', 'MicrosoftTeams',
  'Clipchamp.Clipchamp', 'Microsoft.PowerAutomateDesktop', 'Microsoft.Windows.DevHome',
  'Microsoft.WindowsFeedbackHub', 'Microsoft.MicrosoftSolitaireCollection', 'Microsoft.BingNews',
  'Microsoft.BingWeather', 'MicrosoftWindows.CrossDevice', 'Microsoft.Edge.GameAssist',
  'AppUp.IntelGraphicsControlPanel', 'Microsoft.549981C3F5F10', 'Microsoft.MicrosoftOfficeHub',
  'Microsoft.OutlookForWindows', 'Microsoft.Todos', 'Microsoft.People', 'Microsoft.GetHelp',
  'Microsoft.WindowsSoundRecorder', 'MicrosoftCorporationII.QuickAssist'
)
if ($RemoveIntelApp) { $Apps += 'AppUp.IntelGraphicsExperience' }
try {
  $provisioned = Get-AppxProvisionedPackage -Online -ErrorAction Stop
} catch { Write-YaroFailure "provisioned app inventory: $($_.Exception.Message)" }
$provisioned | Where-Object { $_.DisplayName -in $Apps } | ForEach-Object {
  "  remove provisioned $($_.DisplayName)"
  $package = $_
  try { Remove-AppxProvisionedPackage -Online -AllUsers -PackageName $package.PackageName -ErrorAction Stop | Out-Null }
  catch { Write-YaroFailure "remove provisioned $($package.DisplayName): $($_.Exception.Message)" }
}
if ($Live) {
  $installedApps = $null
  try { $installedApps = @(Get-AppxPackage -AllUsers -ErrorAction Stop | Where-Object { $_.Name -in $Apps }) }
  catch { "  WARN app inventory unavailable; querying packages by name" }
  foreach ($a in $Apps) {
    $packages = if ($null -eq $installedApps) {
      try { Get-AppxPackage -AllUsers -Name $a -ErrorAction Stop }
      catch { Write-YaroFailure "query app $a - $($_.Exception.Message)" | Out-Host }
    } else {
      $installedApps.Where({ $_.Name -eq $a })
    }
    foreach ($package in $packages) {
      "  remove installed $($package.Name)"
      try { Remove-AppxPackage -AllUsers -Package $package.PackageFullName -ErrorAction Stop }
      catch { Write-YaroFailure "remove $($package.Name): $($_.Exception.Message)" }
    }
  }
  Remove-YaroCoreAI $UserSid.Value
}

# ---------- 2. Windows capabilities (Features on Demand) ----------
"== Capabilities"
$Caps = @('Hello.Face*', 'Browser.InternetExplorer*', 'App.StepsRecorder*', 'MathRecognizer*',
          'Media.WindowsMediaPlayer*', 'Language.Handwriting*', 'Language.Speech*', 'Print.Fax.Scan*',
          'OneCoreUAP.OneSync*', '*Wallpaper*', 'App.Support.QuickAssist*')
if ($DisableDefender) { $Caps += 'Microsoft.Windows.Sense.Client*' }
try {
  $capabilities = Get-WindowsCapability -Online -ErrorAction Stop
} catch { Write-YaroFailure "capability inventory: $($_.Exception.Message)" }
$capabilities | Where-Object {
  $name = $_.Name
  $_.State -eq 'Installed' -and $Caps.Where({ $name -like $_ }, 'First').Count -gt 0
} | ForEach-Object {
  "  remove $($_.Name)"
  $capability = $_.Name
  try { Remove-WindowsCapability -Online -Name $capability -ErrorAction Stop | Out-Null }
  catch {
    if (Test-YaroPermanentPackageError $_) { "  NOTE capability $capability is permanent on this Windows build; left as is" }
    else { Write-YaroFailure "remove capability $capability - $($_.Exception.Message)" }
  }
}

# ---------- 3. Optional features ----------
"== Optional features"
$disableFeatures = @('SMB1Protocol', 'MicrosoftWindowsPowerShellV2', 'MicrosoftWindowsPowerShellV2Root',
                     'Printing-XPSServices-Features', 'WorkFolders-Client', 'MSRDC-Infrastructure', 'MediaPlayback')
if ($DisableWindowsAI) { $disableFeatures += 'Recall' }
$features = @{}
try {
  foreach ($feature in (Get-WindowsOptionalFeature -Online -ErrorAction Stop)) {
    $features[$feature.FeatureName] = $feature.State
  }
} catch { Write-YaroFailure "optional feature inventory: $($_.Exception.Message)" }
foreach ($name in $disableFeatures) {
  if ($features[$name] -eq 'Enabled') {
    "  disable $name"
    try { Disable-WindowsOptionalFeature -Online -FeatureName $name -NoRestart -WarningAction SilentlyContinue -ErrorAction Stop | Out-Null }
    catch {
      if (Test-YaroPermanentPackageError $_) { "  NOTE feature $name is permanent on this Windows build; left as is" }
      else { Write-YaroFailure "disable feature $name - $($_.Exception.Message)" }
    }
  }
}
# The kernel file carries the servicing build even on releases installed by enablement package.
if ($features['NetFx3'] -in 'Disabled', 'DisabledWithPayloadRemoved') {
  $version = [Diagnostics.FileVersionInfo]::GetVersionInfo((Join-Path $env:SystemRoot 'System32\ntoskrnl.exe'))
  $baseVersion = '{0}.{1}.{2}' -f $version.FileMajorPart, $version.FileMinorPart, $version.FileBuildPart
  $identity = "Microsoft-Windows-NetFx3-OnDemand-Package~31bf3856ad364e35~$env:PROCESSOR_ARCHITECTURE~~"
  $source = $null
  foreach ($drive in [IO.DriveInfo]::GetDrives()) {
    if ($drive.DriveType -notin 'Fixed', 'Removable', 'CDRom' -or -not $drive.IsReady) { continue }
    $sxs = Join-Path $drive.RootDirectory.FullName 'sources\sxs'
    $cab = Join-Path $sxs "$identity.cab"
    if (-not (Test-Path -LiteralPath $cab -PathType Leaf)) { continue }
    try {
      $package = Get-WindowsPackage -Online -PackagePath $cab -ErrorAction Stop
      if ($package.PackageName -like "$identity$baseVersion.*") { $source = $sxs; break }
      "  skipped incompatible NetFx3 package: $($package.PackageName)"
    } catch { "  WARN cannot verify NetFx3 source $cab - $($_.Exception.Message)" }
  }
  if ($source) {
    "  enable NetFx3 from $source"
    & dism.exe /Online /Enable-Feature /FeatureName:NetFx3 /All /LimitAccess "/Source:$source" /NoRestart *> $null
    if ($LASTEXITCODE -notin 0, 3010) { Write-YaroFailure "enable NetFx3 (DISM exit $LASTEXITCODE)" }
  } else { "  skipped NetFx3 (no matching installation media)" }
}

# ---------- 4. Services ----------
"== Services"
foreach ($s in 'DiagTrack', 'dmwappushservice', 'MapsBroker', 'RetailDemo', 'CDPSvc', 'CDPUserSvc',
               'TermService', 'WSAIFabricSvc', 'PcaSvc', 'InventorySvc', 'TrkWks',
               'whesvc', 'lfsvc', 'SharedAccess', 'PhoneSvc', 'WalletService') { Svc $s 4 }
foreach ($s in 'WerSvc', 'XblAuthManager', 'XblGameSave', 'XboxNetApiSvc', 'XboxGipSvc', 'RmSvc') { Svc $s 3 }
foreach ($s in 'SysMain', 'DPS') { Svc $s 2 }
if ($DisablePrinting)    { Svc 'Spooler' 4; Svc 'PrintNotify' 4; Svc 'PrintWorkflowUserSvc' 4 }
if ($DisableBtHandsFree) { Svc 'BTAGService' 4 }
if ($DisableVPN)         { Svc 'RasMan' 4; Svc 'RasAuto' 4 }
if ($RemoveOneDrive)     { Svc 'OneSyncSvc' 4 }
if ($DisableSearchIndex) { Svc 'WSearch' 4; if ($Live) { & sc.exe stop WSearch *> $null } }
if ($RemoveIntelApp)     { Svc 'igccservice' 4 }
# A disabled per-user template still creates a service instance at each sign-in if UserServiceFlags is 3.
foreach ($tmpl in 'CDPUserSvc', 'PrintWorkflowUserSvc', 'OneSyncSvc') { Clear-YaroUserServiceTemplate $tmpl }
Set-YaroRegistryValue 'HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server' 'fDenyTSConnections' '1'

# ---------- 5. Setup, updates, telemetry, privacy ----------
"== Registry: setup, updates, privacy"
Set-YaroRegistryValue 'HKLM\SYSTEM\CurrentControlSet\Control\BitLocker' 'PreventDeviceEncryption' '1'
Set-YaroRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\OOBE' 'DisableOOBEUpdate' '1'
Set-YaroRegistryValue 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE' 'DisableOOBEUpdate' '1'
Set-YaroRegistryValue 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE' 'HideOOBEUpdate' '1'
if ($PauseUpdates) {
  $ux = 'HKLM\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
  Set-YaroRegistryValue $ux 'PauseUpdatesExpiryTime' '2077-01-01T00:00:00Z' 'REG_SZ'
  Set-YaroRegistryValue $ux 'PauseFeatureUpdatesStartTime' '2026-01-01T00:00:00Z' 'REG_SZ'
  Set-YaroRegistryValue $ux 'PauseFeatureUpdatesEndTime' '2077-01-01T00:00:00Z' 'REG_SZ'
  Set-YaroRegistryValue $ux 'PauseQualityUpdatesStartTime' '2026-01-01T00:00:00Z' 'REG_SZ'
  Set-YaroRegistryValue $ux 'PauseQualityUpdatesEndTime' '2077-01-01T00:00:00Z' 'REG_SZ'
  Set-YaroRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'NoAutoUpdate' '1'
}
Set-YaroRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' 'ExcludeWUDriversInQualityUpdate' '1'
Set-YaroRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' '0'
Set-YaroRegistryValue 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' 'AllowTelemetry' '0'
Set-YaroRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'DoNotShowFeedbackNotifications' '1'
# Advertising ID off for every user by policy; apps cannot get it and the switch in Settings stays locked
Set-YaroRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo' 'DisabledByGroupPolicy' '1'
Set-YaroRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\System' 'EnableActivityFeed' '0'
Set-YaroRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\System' 'PublishUserActivities' '0'
Set-YaroRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\System' 'UploadUserActivities' '0'
Set-YaroRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\System' 'EnableCdp' '0'
Set-YaroRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' '1'
Set-YaroRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableConsumerAccountStateContent' '1'
Set-YaroRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableCloudOptimizedContent' '1'
Set-YaroRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\PushToInstall' 'DisablePushToInstall' '1'
Set-YaroRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\MRT' 'DontOfferThroughWUAU' '1'
Set-YaroRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Teams' 'DisableInstallation' '1'
Set-YaroRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Mail' 'PreventRun' '1'
Set-YaroRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Chat' 'ChatIcon' '3'
if (-not $Live) {
  Set-YaroRegistryValue 'HKLM\SOFTWARE\Microsoft\PolicyManager\current\device\Start' 'ConfigureStartPins' '{"pinnedList": [{}]}' 'REG_SZ'
}
# Prevent Windows Update OOBE orchestrator from silently re-installing Outlook and Dev Home
Set-YaroRegistryValue 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate' 'workCompleted' '1'
Set-YaroRegistryValue 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\OutlookUpdate' 'workCompleted' '1'
Set-YaroRegistryValue 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\DevHomeUpdate' 'workCompleted' '1'
foreach ($oobeTask in 'OutlookUpdate', 'DevHomeUpdate') {
  $oobePath = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\$oobeTask"
  if (Test-Path -LiteralPath $oobePath) { Remove-Item -LiteralPath $oobePath -Recurse -Force -ErrorAction SilentlyContinue }
}
Set-YaroRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' '0'
Set-YaroRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Connect' 'AllowProjectionToPC' '0'
Set-YaroRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\LiveCaptions' 'AllowLiveCaptions' '0'
Set-YaroRegistryValue 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' 'Value' 'Deny' 'REG_SZ'
Set-YaroRegistryValue 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Sensor\Overrides\{BFA794E4-F964-4FDB-90F6-51056BFE4B44}' 'SensorPermissionState' '0'
Set-YaroRegistryValue 'HKLM\SYSTEM\CurrentControlSet\Services\lfsvc\Service\Configuration' 'Status' '0'
Set-YaroRegistryValue 'HKLM\SYSTEM\Maps' 'AutoUpdateEnabled' '0'
Set-YaroRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' '0'
if ($DisableWindowsAI) {
  Set-YaroRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' '1'
  Set-YaroRegistryValue 'HKLM\SOFTWARE\Policies\WindowsNotepad' 'DisableAIFeatures' '1'
  Set-YaroRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' '1'
  Set-YaroRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'AllowRecallEnablement' '0'
  Set-YaroRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableClickToDo' '1'
}
Set-YaroRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' '0'
Set-YaroRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\StorageSense' 'AllowStorageSenseGlobal' '0'
$oneDrivePolicy = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive'
Set-YaroRegistryValue $oneDrivePolicy 'DisableFileSyncNGSC' '1'
Set-YaroRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\WindowsInkWorkspace' 'AllowWindowsInkWorkspace' '0'
Set-YaroRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\PassportForWork' 'Enabled' '0'
Set-YaroRegistryValue 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'NoDriveTypeAutoRun' '255'
if ($DisableBgApps) {
  Set-YaroRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' 'LetAppsRunInBackground' '2'
}
if ($DebloatEdge) {
  Set-YaroRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\EdgeUpdate' 'CreateDesktopShortcutDefault' '0'
  $edgePol = 'HKLM\SOFTWARE\Policies\Microsoft\Edge'
  Set-YaroRegistryValue $edgePol 'StartupBoostEnabled' '0'
  Set-YaroRegistryValue $edgePol 'BackgroundModeEnabled' '0'
  Set-YaroRegistryValue $edgePol 'HubsSidebarEnabled' '0'
  Set-YaroRegistryValue $edgePol 'PersonalizationReportingEnabled' '0'
  Set-YaroRegistryValue $edgePol 'ShowRecommendationsEnabled' '0'
  Set-YaroRegistryValue $edgePol 'HideFirstRunExperience' '1'
  Set-YaroRegistryValue $edgePol 'UserFeedbackAllowed' '0'
  Set-YaroRegistryValue $edgePol 'ConfigureDoNotTrack' '1'
  Set-YaroRegistryValue $edgePol 'AlternateErrorPagesEnabled' '0'
  Set-YaroRegistryValue $edgePol 'EdgeCollectionsEnabled' '0'
  Set-YaroRegistryValue $edgePol 'EdgeShoppingAssistantEnabled' '0'
  Set-YaroRegistryValue $edgePol 'MicrosoftEdgeInsiderPromotionEnabled' '0'
  Set-YaroRegistryValue $edgePol 'ShowMicrosoftRewards' '0'
  Set-YaroRegistryValue $edgePol 'WebWidgetAllowed' '0'
  Set-YaroRegistryValue $edgePol 'DiagnosticData' '0'
  Set-YaroRegistryValue $edgePol 'EdgeAssetDeliveryServiceEnabled' '0'
  Set-YaroRegistryValue $edgePol 'WalletDonationEnabled' '0'
  Set-YaroRegistryValue $edgePol 'DefaultBrowserSettingsCampaignEnabled' '0'
  Set-YaroRegistryValue "$edgePol\ExtensionInstallBlocklist" '1' 'ofefcgjbeghpigppfmkologfjadafddi' 'REG_SZ'
}
if ($EnablePhotoViewer) {
  $pvKey = 'HKLM\SOFTWARE\Microsoft\Windows Photo Viewer\Capabilities\FileAssociations'
  foreach ($ext in '.bmp', '.dib', '.gif', '.ico', '.jfif', '.jpe', '.jpeg', '.jpg', '.jxr', '.png', '.tif', '.tiff', '.wdp') {
    Set-YaroRegistryValue $pvKey $ext 'PhotoViewer.FileAssoc.Tiff' 'REG_SZ'
  }
}

# ---------- 6. Search (no web results, no WebView2 in Search) ----------
"== Registry: search"
$fm = 'HKLM\SYSTEM\CurrentControlSet\Control\FeatureManagement\Overrides\8\1694661260'
Set-YaroRegistryValue $fm 'EnabledState' '1'; Set-YaroRegistryValue $fm 'EnabledStateOptions' '0'; Set-YaroRegistryValue $fm 'Variant' '0'
Set-YaroRegistryValue $fm 'VariantPayload' '0'; Set-YaroRegistryValue $fm 'VariantPayloadKind' '0'
Set-YaroRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'EnableDynamicContentInWSB' '0'
Set-YaroRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'DisableWebSearch' '1'
Set-YaroRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'ConnectedSearchUseWeb' '0'
Set-YaroRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search' 'AllowCloudSearch' '0'

# ---------- 7. Fast installers and drivers (no 2-minute CRL hangs) ----------
"== Registry: installers and drivers"
foreach ($k in 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WinTrust\Trust Providers\Software Publishing',
               'HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\WinTrust\Trust Providers\Software Publishing',
               'HKU\.DEFAULT\Software\Microsoft\Windows\CurrentVersion\WinTrust\Trust Providers\Software Publishing') {
  Set-YaroRegistryValue $k 'State' '0x00023c00'
}
foreach ($k in 'HKLM\SOFTWARE\Microsoft\Cryptography\OID\EncodingType 0\CertDllCreateCertificateChainEngine\Config',
               'HKLM\SOFTWARE\WOW6432Node\Microsoft\Cryptography\OID\EncodingType 0\CertDllCreateCertificateChainEngine\Config',
               'HKLM\SOFTWARE\Policies\Microsoft\SystemCertificates\ChainEngine\Config',
               'HKLM\SOFTWARE\WOW6432Node\Policies\Microsoft\SystemCertificates\ChainEngine\Config') {
  Set-YaroRegistryValue $k 'ChainUrlRetrievalTimeoutMilliseconds' '200'
  Set-YaroRegistryValue $k 'ChainRevAccumulativeUrlRetrievalTimeoutMilliseconds' '500'
}
Set-YaroRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\Installer' 'LimitSystemRestoreCheckpointing' '1'
Set-YaroRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DriverSearching' 'DontSearchWindowsUpdate' '1'
Set-YaroRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DriverSearching' 'SearchOrderConfig' '0'
Set-YaroRegistryValue 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching' 'SearchOrderConfig' '0'
Set-YaroRegistryValue 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Device Metadata' 'PreventDeviceMetadataFromNetwork' '1'
Set-YaroRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Settings' 'DisableSendGenericDriverNotFoundToWER' '1'
Set-YaroRegistryValue 'HKLM\SYSTEM\CurrentControlSet\Control\CI\Policy' 'VerifiedAndReputablePolicyState' '0'

# ---------- 8. Performance, memory, file system ----------
"== Registry: performance"
Set-YaroRegistryValue 'HKLM\SYSTEM\CurrentControlSet\Control' 'SvcHostSplitThresholdInKB' '0xffffffff'
Set-YaroRegistryValue 'HKLM\SYSTEM\CurrentControlSet\Control' 'WaitToKillServiceTimeout' '5000' 'REG_SZ'
Set-YaroRegistryValue 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager' 'DisableWpbtExecution' '1'
Set-YaroRegistryValue 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' '0'
Set-YaroRegistryValue 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' 'DisablePagingExecutive' '1'
Set-YaroRegistryValue 'HKLM\SYSTEM\CurrentControlSet\Control\CrashControl' 'DisplayParameters' '1'
Set-YaroRegistryValue 'HKLM\SYSTEM\CurrentControlSet\Control\CrashControl' 'DisableEmoticon' '1'
Set-YaroRegistryValue 'HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard' 'EnableVirtualizationBasedSecurity' '0'
Set-YaroRegistryValue 'HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled' '0'
Set-YaroRegistryValue 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' '2'
Set-YaroRegistryValue 'HKLM\SYSTEM\CurrentControlSet\Control\FileSystem' 'LongPathsEnabled' '1'
Set-YaroRegistryValue 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager' 'ShippedWithReserves' '0'
Set-YaroRegistryValue 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' 'AllowDevelopmentWithoutDevLicense' '1'
Set-YaroRegistryValue 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NetworkThrottlingIndex' '0xffffffff'
if ($PreferIPv4) {
  $tcpip6Key = 'HKLM\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters'
  $curComp = [Microsoft.Win32.Registry]::GetValue("HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters", 'DisabledComponents', 0)
  $newComp = if ($curComp -is [int]) { $curComp -bor 32 } else { 32 }
  Set-YaroRegistryValue $tcpip6Key 'DisabledComponents' ([string]$newComp)
}
if ($DisableHibernation) {
  Set-YaroRegistryValue 'HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HibernateEnabled' '0'
  Set-YaroRegistryValue 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings' 'ShowHibernateOption' '0'
  & powercfg.exe /hibernate off *> $null
}
& fsutil.exe behavior set disablelastaccess 1 *> $null
if ($LASTEXITCODE -ne 0) { Write-YaroFailure "set NTFS last-access behavior (exit $LASTEXITCODE)" }
& dism.exe /Online /Set-ReservedStorageState /State:Disabled *> $null
if ($LASTEXITCODE -notin 0, 3010) { Write-YaroFailure "disable reserved storage (DISM exit $LASTEXITCODE)" }
[Environment]::SetEnvironmentVariable('POWERSHELL_TELEMETRY_OPTOUT', '1', 'Machine')
[Environment]::SetEnvironmentVariable('DOTNET_CLI_TELEMETRY_OPTOUT', '1', 'Machine')
if ($ArgonPerformance) {
  "== Argon performance"
  # Power throttling only slows BACKGROUND apps (never the active game). Keeping it on leaves more
  # turbo/thermal headroom for the game and lets 12-14th gen Intel move background work to E-cores.
  # Earlier Yaro versions turned it off, so the old value is removed.
  Remove-YaroRegistryValue 'HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' 'PowerThrottlingOff'
  # MMCSS reserve for background tasks: Windows treats 0 as 10, so 10 is the lowest effective value.
  Set-YaroRegistryValue 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'SystemResponsiveness' '10'
  & fsutil.exe 8dot3name set 1 *> $null
  if ($LASTEXITCODE -ne 0) { Write-YaroFailure "turn off 8.3 short names (exit $LASTEXITCODE)" }
}
if ($ForceMSI) {
  "== MSI mode for GPU, NVMe and network adapters"
  try {
    Get-PnpDevice -PresentOnly -ErrorAction Stop |
      Where-Object { $_.Class -in 'Display', 'SCSIAdapter', 'Net' -and $_.InstanceId -like 'PCI\*' } |
      ForEach-Object {
        $msi = "SYSTEM\CurrentControlSet\Enum\$($_.InstanceId)\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
        if (Test-Path -LiteralPath "HKLM:\$msi" -ErrorAction SilentlyContinue) {
          Set-YaroRegistryValue "HKLM\$msi" 'MSISupported' '1'
          "  MSI on: $($_.FriendlyName)"
        }
      }
  } catch { Write-YaroFailure "MSI mode: $($_.Exception.Message)" }
}

# ---------- 9. Explorer: "Open in Notepad" for every file ----------
try {
  $notepad = Join-Path $env:SystemRoot 'System32\notepad.exe'
  $k = [Microsoft.Win32.Registry]::LocalMachine.CreateSubKey('SOFTWARE\Classes\*\shell\YaroOpenInNotepad')
  $k.SetValue('', 'Open in Notepad'); $k.SetValue('Icon', $notepad)
  $c = $k.CreateSubKey('command'); $c.SetValue('', ('"{0}" "%1"' -f $notepad)); $c.Close(); $k.Close()
} catch { Write-YaroFailure "Open in Notepad: $($_.Exception.Message)" }

# ---------- Windows Temp permissions (installers fail with errors 2503/2502 when broken) ----------
"== Windows Temp permissions"
Repair-YaroWindowsTemp

# ---------- 10. Security options ----------
"== Security options"
if ($SilentUAC) { Set-YaroRegistryValue 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'ConsentPromptBehaviorAdmin' '0' }
if ($DisableSmartScreen) {
  Set-YaroRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows\System' 'EnableSmartScreen' '0'
  Set-YaroRegistryValue 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer' 'SmartScreenEnabled' 'Off' 'REG_SZ'
}
if ($DisableDefender) {
  $d = 'HKLM\SOFTWARE\Policies\Microsoft\Windows Defender'
  Set-YaroRegistryValue $d 'DisableAntiSpyware' '1'
  Set-YaroRegistryValue $d 'DisableAntiVirus' '1'
  Set-YaroRegistryValue "$d\Real-Time Protection" 'DisableRealtimeMonitoring' '1'
  Set-YaroRegistryValue "$d\Real-Time Protection" 'DisableBehaviorMonitoring' '1'
  Set-YaroRegistryValue "$d\Real-Time Protection" 'DisableOnAccessProtection' '1'
  Set-YaroRegistryValue "$d\Real-Time Protection" 'DisableScanOnRealtimeEnable' '1'
  Set-YaroRegistryValue "$d\Real-Time Protection" 'DisableIOAVProtection' '1'
  Set-YaroRegistryValue "$d\Spynet" 'SpynetReporting' '0'
  Set-YaroRegistryValue "$d\Spynet" 'SubmitSamplesConsent' '2'
  Set-YaroRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Systray' 'HideSystray' '1'
  Set-YaroRegistryValue 'HKLM\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Notifications' 'DisableNotifications' '1'
  # While Defender runs, Windows locks its services (even for SYSTEM during setup).
  $locked = @()
  # The Security tray icon is useless while Defender is off
  Remove-YaroRegistryValue 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' 'SecurityHealth'
  foreach ($s in 'WinDefend', 'WdNisSvc', 'Sense', 'MDCoreSvc', 'webthreatdefsvc', 'webthreatdefusersvc', 'wscsvc', 'SecurityHealthService', 'WdFilter', 'WdBoot', 'WdNisDrv') {
    $subkey = "SYSTEM\CurrentControlSet\Services\$s"
    if (-not (Test-Path -LiteralPath "HKLM:\$subkey" -ErrorAction SilentlyContinue)) { continue }
    if ((Get-ItemProperty -LiteralPath "HKLM:\$subkey" -Name Start -ErrorAction SilentlyContinue).Start -eq 4) { continue }
    try { [Microsoft.Win32.Registry]::SetValue("HKEY_LOCAL_MACHINE\$subkey", 'Start', 4, [Microsoft.Win32.RegistryValueKind]::DWord) }
    catch { $locked += $s }
  }
  Clear-YaroUserServiceTemplate 'webthreatdefusersvc'
  if ($locked) { "  NOTE Windows protects the Defender services ($($locked -join ', ')); they stay as they are" }
  # With Tamper Protection on, Defender ignores the policies above.
  $tamper = $null
  try { $tamper = (Get-MpComputerStatus -ErrorAction Stop).IsTamperProtected } catch { }
  if ($tamper -eq $true) {
    $how = 'Tamper Protection is on, so Defender ignores these settings. Turn it off (Windows Security > Virus & threat protection > Manage settings), then run Yaro-Apply.cmd again'
    if ($Live) { Write-YaroFailure "Defender stays on: $how" } else { "  NOTE Defender stays on: $how" }
  }
}

# ---------- 11. Intel telemetry (only if Intel software installed it) ----------
"== Intel telemetry cleanup"
$intelProduct = '{420234D0-4C97-4B9F-B997-EC2AFDC5C695}'
try {
  $installer = New-Object -ComObject WindowsInstaller.Installer -ErrorAction Stop
  if ($installer.ProductState($intelProduct) -in 1, 5) {
    $result = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\msiexec.exe') -ArgumentList "/x $intelProduct /qn /norestart" -Wait -PassThru -WindowStyle Hidden -ErrorAction Stop
    if ($result.ExitCode -notin 0, 1605, 1614, 3010) { Write-YaroFailure "uninstall Intel telemetry (MSI exit $($result.ExitCode))" }
  }
} catch { Write-YaroFailure "Intel telemetry MSI: $($_.Exception.Message)" }
foreach ($s in 'ESRV_SVC_QUEENCREEK', 'USER_ESRV_SVC_QUEENCREEK', 'SystemUsageReportSvc_QUEENCREEK', 'Intel(R) SUR QC SAM', 'semav6msr64') {
  if (Test-Path -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\$s" -ErrorAction SilentlyContinue) {
    & sc.exe stop $s *> $null
    & sc.exe delete $s *> $null
    if ($LASTEXITCODE -ne 0) { Write-YaroFailure "delete Intel telemetry service $s (exit $LASTEXITCODE)" }
  }
}
foreach ($s in 'IntelTelemetryAgent', 'IntelCollectorService') { Svc $s 4 }
Svc 'PresentMonSharedService' 3
# Service of the old "Intel HD Graphics Control Panel" app, which Yaro removes (AppUp.IntelGraphicsControlPanel).
# Manual = it no longer runs all the time but can still start if that panel is installed again.
Svc 'igfxCUIService2.0.0.0' 3

# ---------- 12. Background scheduled tasks ----------
"== Scheduled tasks"
try {
  $scheduler = New-Object -ComObject Schedule.Service -ErrorAction Stop
  $scheduler.Connect()
  $folder = $scheduler.GetFolder('\')
  $taskPaths = '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
             '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser Exp',
             '\Microsoft\Windows\Application Experience\MareBackup',
             '\Microsoft\Windows\Application Experience\PcaPatchDbTask',
             '\Microsoft\Windows\Application Experience\StartupAppTask',
             '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
             '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
             '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector',
             '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticResolver',
             '\Microsoft\Windows\Maintenance\WinSAT',
             '\Microsoft\Windows\Flighting\FeatureConfig\UsageDataReporting',
             '\Microsoft\Windows\Flighting\FeatureConfig\UsageDataFlushing',
             '\Microsoft\Windows\Flighting\FeatureConfig\UsageDataReceiver',
             '\Microsoft\Windows\Flighting\FeatureConfig\GovernedFeatureUsageProcessing',
             '\Microsoft\Windows\Flighting\FeatureConfig\ReconcileConfigs',
             '\Microsoft\Windows\Flighting\FeatureConfig\ReconcileFeatures',
             '\Microsoft\Windows\Flighting\FeatureConfig\SafeguardsReconciliation',
             '\Microsoft\Windows\Flighting\OneSettings\RefreshCache',
             '\Microsoft\Windows\Feedback\Siuf\DmClient',
             '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload',
             '\Microsoft\Windows\Windows Error Reporting\QueueReporting',
             '\Microsoft\Windows\Diagnosis\RecommendedTroubleshootingScanner',
             '\Microsoft\Windows\Diagnosis\Scheduled',
             '\Microsoft\Windows\Diagnosis\UnexpectedCodepath',
             '\Microsoft\Windows\Shell\FamilySafetyMonitor',
             '\Microsoft\Windows\Shell\FamilySafetyRefreshTask',
             '\Microsoft\Windows\Maps\MapsToastTask',
             '\Microsoft\Windows\RetailDemo\CleanupOfflineContent',
             '\Microsoft\Windows\Autochk\Proxy',
             '\Microsoft\Windows\Device Information\Device',
             '\Microsoft\Windows\Device Information\Device User',
             '\Microsoft\Windows\Sustainability\SustainabilityTelemetry',
             '\Microsoft\Windows\PerformanceTrace\ShowFeedbackToast',
             '\Microsoft\Windows\PerformanceTrace\WhesvcToast',
             '\Microsoft\Windows\AccountHealth\RecoverabilityToastTask',
             '\Microsoft\Windows\Power Efficiency Diagnostics\AnalyzeSystem',
             '\USER_ESRV_SVC_QUEENCREEK'
  # Defender's own tasks only fail while Defender is off. Windows may protect them, so a refusal is just a note.
  $quietTasks = @()
  if ($DisableDefender) {
    $quietTasks = 'Cache Maintenance', 'Cleanup', 'Scheduled Scan', 'Verification' |
      ForEach-Object { "\Microsoft\Windows\Windows Defender\Windows Defender $_" }
  }
  $taskPaths = @($taskPaths) + $quietTasks
  foreach ($path in $taskPaths) {
    try {
      $task = $folder.GetTask($path)
      if ($path -eq '\USER_ESRV_SVC_QUEENCREEK') {
        $folder.DeleteTask('USER_ESRV_SVC_QUEENCREEK', 0)
      } elseif ($task.Enabled) {
        $task.Enabled = $false
      }
    } catch {
      # A missing task or parent folder is normal across Windows editions.
      if ($_.Exception.GetBaseException().HResult -notin 0x80070002, 0x80070003) {
        if ($path -in $quietTasks) { "  NOTE scheduled task $path is protected by Windows; left as is" }
        else { Write-YaroFailure "scheduled task $path - $($_.Exception.Message)" }
      }
    }
  }
} catch { Write-YaroFailure "connect to Task Scheduler: $($_.Exception.Message)" }

# The reporting task shares a binary with the updater. Match its action as well as its name.
try {
  if (Test-YaroOneDriveInactive) {
    $tasks = @(Get-ScheduledTask -ErrorAction Stop |
      Where-Object { $_.TaskPath -eq '\' -and $_.TaskName -like 'OneDrive Reporting Task-S-1-*' })
    foreach ($task in $tasks) {
      if ($task.State -eq 'Disabled' -or -not (Test-YaroOneDriveReportingTask $task)) { continue }
      try {
        Disable-ScheduledTask -InputObject $task -ErrorAction Stop | Out-Null
        "  disabled OneDrive reporting task"
      } catch {
        Write-YaroFailure "disable OneDrive reporting: $($_.Exception.Message)"
      }
    }
  }
} catch { Write-YaroFailure "check OneDrive reporting: $($_.Exception.Message)" }

# ---------- 13. Wallpaper ----------
if ($SetWallpaper) {
  "== Wallpaper"
  $Wp = $YaroWallpaperPath
  $YaroDir = $YaroLogDir
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Wp), $YaroDir | Out-Null
  $B64 = Join-Path $YaroDir 'yaro-wallpaper.b64'                              # clean install: from autounattend.xml
  $RepoPng = Join-Path $PSScriptRoot '..\assets\yaro-wallpaper-cream.png'      # Yaro-Apply.cmd: from the repository
  try {
    if (-not $Live -and (Test-Path -LiteralPath $B64)) {
      [IO.File]::WriteAllBytes($Wp, [Convert]::FromBase64String((Get-Content -LiteralPath $B64 -Raw -ErrorAction Stop)))
      Remove-Item -LiteralPath $B64 -Force -ErrorAction Stop
    } elseif (Test-Path -LiteralPath $RepoPng) {
      Copy-Item -LiteralPath $RepoPng -Destination $Wp -Force -ErrorAction Stop
    } elseif (-not (Test-Path -LiteralPath $Wp)) {
      throw 'Wallpaper image not found'
    }
    $Sw = Join-Path $PSScriptRoot 'SetWallpaper.ps1'
    $destination = Join-Path $YaroDir 'SetWallpaper.ps1'
    if ($Sw -ne $destination) { Copy-Item -LiteralPath $Sw -Destination $destination -Force -ErrorAction Stop }
    "  wallpaper: $Wp"
  } catch { Write-YaroFailure "wallpaper: $($_.Exception.Message)" }
}

# ---------- 14. Default user profile (applies to every new user) ----------
"== Default user profile"
$profileList = 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
$defaultProfile = [Microsoft.Win32.Registry]::GetValue($profileList, 'Default', $null)
if (-not $defaultProfile) { $defaultProfile = Join-Path $env:SystemDrive 'Users\Default' }
$defaultHive = Join-Path ([Environment]::ExpandEnvironmentVariables($defaultProfile)) 'NTUSER.DAT'
& reg.exe load 'HKU\YaroDefault' $defaultHive *> $null
if ($LASTEXITCODE -eq 0) {
  try {
    Set-YaroUserSettings 'HKU\YaroDefault'
    Set-YaroUserPolicies 'HKU\YaroDefault'
    $wallpaperRunOnce = 'HKU\YaroDefault\Software\Microsoft\Windows\CurrentVersion\RunOnce'
    $wallpaperCommand = 'powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f (Join-Path $YaroLogDir 'SetWallpaper.ps1')
    if ($SetWallpaper -and (Test-Path -LiteralPath $YaroWallpaperPath)) {
      Set-YaroRegistryValue 'HKU\YaroDefault\Control Panel\Desktop' 'Wallpaper' $YaroWallpaperPath 'REG_SZ'
      Set-YaroRegistryValue 'HKU\YaroDefault\Control Panel\Desktop' 'WallpaperStyle' '10' 'REG_SZ'
      Set-YaroRegistryValue $wallpaperRunOnce 'YaroWallpaper' "$wallpaperCommand -Once" 'REG_SZ'
    } elseif (-not $SetWallpaper) {
      $runOncePath = 'Registry::' + (Get-YaroRegistryPath $wallpaperRunOnce)
      $queued = Get-ItemPropertyValue -LiteralPath $runOncePath -Name YaroWallpaper -ErrorAction SilentlyContinue
      $legacyCommand = $wallpaperCommand.Replace('"', '')
      if ($queued -in $wallpaperCommand, "$wallpaperCommand -Once", $legacyCommand, "$legacyCommand -Once") {
        try { Remove-ItemProperty -LiteralPath $runOncePath -Name YaroWallpaper -ErrorAction Stop }
        catch { Write-YaroFailure "clear pending wallpaper: $($_.Exception.Message)" }
      }
    }
    Remove-YaroOneDriveStartup 'HKU\YaroDefault'
  } finally {
    [gc]::Collect()
    & reg.exe unload 'HKU\YaroDefault' *> $null
    if ($LASTEXITCODE -ne 0) { Write-YaroFailure "unload default user hive (exit $LASTEXITCODE)" }
  }
} else { Write-YaroFailure "could not load the default user hive: $defaultHive" }

if ($Live) {
  $userHive = "HKU\$($UserSid.Value)"
  if (Test-Path -LiteralPath "Registry::HKEY_USERS\$($UserSid.Value)") {
    Set-YaroUserPolicies $userHive
  } else { Write-YaroFailure "signed-in user's registry hive unavailable: $UserSid" }
  Set-YaroMachinePerformance
}

"Yaro Specialize.ps1 finished $(Get-Date)"
Stop-Transcript | Out-Null
if ($Live) {
  if ($script:YaroFailures) { exit 2 }
  exit 0
}
