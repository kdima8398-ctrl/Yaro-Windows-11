# =============================================================================
#  Yaro - puts the Yaro wallpaper on the desktop of the signed-in user.
#  Runs from FirstLogon.ps1 and once for every new user (RunOnce).
#  The image: %SystemRoot%\Web\Wallpaper\Yaro\yaro-wallpaper.png
# =============================================================================
param([switch]$Once)

$p = Join-Path $env:SystemRoot 'Web\Wallpaper\Yaro\yaro-wallpaper.png'
if (-not (Test-Path -LiteralPath $p)) { return }

$mutex = $null
$locked = $false
try {
  if ($Once) {
    # RunOnce and the setup's FirstLogon command can overlap in the same session.
    $stateKey = 'HKEY_CURRENT_USER\Software\Yaro'
    try {
      $mutex = [System.Threading.Mutex]::new($false, 'Local\Yaro.SetupWallpaper')
      try { $locked = $mutex.WaitOne(5000) } catch [System.Threading.AbandonedMutexException] { $locked = $true }
      if ($locked -and [Microsoft.Win32.Registry]::GetValue($stateKey, 'AppliedSetupWallpaper', $null) -eq $p) {
        "  wallpaper already applied during setup"
        return
      }
    } catch {
      "  WARN could not check whether the wallpaper was already applied: $($_.Exception.Message)"
    }
  }

  Set-ItemProperty -LiteralPath 'HKCU:\Control Panel\Desktop' -Name WallpaperStyle -Value '10'   # Fill
  Set-ItemProperty -LiteralPath 'HKCU:\Control Panel\Desktop' -Name TileWallpaper -Value '0'
  if (-not ('Yaro.Desktop' -as [type])) {
    Add-Type -Namespace Yaro -Name Desktop -MemberDefinition '[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);' -ErrorAction Stop
  }
  if ([Yaro.Desktop]::SystemParametersInfo(0x14, 0, $p, 3) -eq 0) { throw 'Windows could not apply the Yaro wallpaper.' }
  if ($locked) {
    try { [Microsoft.Win32.Registry]::SetValue($stateKey, 'AppliedSetupWallpaper', $p) }
    catch { "  WARN could not record wallpaper application: $($_.Exception.Message)" }
  }
  "  wallpaper set"
} finally {
  if ($locked) { $mutex.ReleaseMutex() }
  if ($mutex) { $mutex.Dispose() }
}
