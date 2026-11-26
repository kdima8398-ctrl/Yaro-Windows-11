@echo off
for /f "tokens=2 delims=:" %%C in ('chcp') do set "YARO_OLD_CP=%%C"
chcp 65001 >nul
setlocal DisableDelayedExpansion
title Yaro — Замер скорости DNS и настройка DoH (IPv4 + IPv6)

set "YARO_SELF=%~f0"
set "YARO_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if exist "%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe" set "YARO_PS=%SystemRoot%\Sysnative\WindowsPowerShell\v1.0\powershell.exe"

set "YARO_CHECK_ONLY="
set "YARO_NO_PAUSE="
:parse_args
if "%~1"=="" goto :args_done
if /i "%~1"=="-CheckOnly" set "YARO_CHECK_ONLY=1"
if /i "%~1"=="-NoPause" set "YARO_NO_PAUSE=1"
shift
goto :parse_args
:args_done

"%YARO_PS%" -NoProfile -ExecutionPolicy Bypass -Command "$c=((Get-Content -LiteralPath $env:YARO_SELF -Raw -Encoding UTF8) -split '(?m)^:: __YARO_PS_START__\r?$',2)[1]; & ([scriptblock]::Create($c))"
set "YARO_ERR=%ERRORLEVEL%"
endlocal & if defined YARO_OLD_CP chcp %YARO_OLD_CP% >nul 2>&1
exit /b %YARO_ERR%

:: __YARO_PS_START__
param(
  [string]$ApplyId,
  [string]$AdapterGuid,
  [switch]$CheckOnly,
  [switch]$NoPause
)

$ErrorActionPreference = 'Stop'
if ($env:YARO_CHECK_ONLY -eq '1') { $CheckOnly = $true }
if ($env:YARO_NO_PAUSE -eq '1') { $NoPause = $true }

try {
  $utf8 = New-Object System.Text.UTF8Encoding($false)
  [Console]::OutputEncoding = $utf8
  [Console]::InputEncoding = $utf8
} catch { }

# Hash our script file at startup to detect TOCTOU tampering before UAC child execution.
$script:SelfHash = $null
if ($env:YARO_SELF -and (Test-Path -LiteralPath $env:YARO_SELF -PathType Leaf)) {
  $script:SelfHash = (Get-FileHash -LiteralPath $env:YARO_SELF -Algorithm SHA256).Hash
}

function Pause-IfInteractive {
  param([string]$Prompt = 'Нажмите Enter для выхода...')
  if ($NoPause) { return }
  Write-Host ''
  Write-Host $Prompt -ForegroundColor DarkGray
  $null = Read-Host
}

function Test-IsAdmin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p = [Security.Principal.WindowsPrincipal]::new($id)
  return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-DohRegistryBase([string]$GuidLower) {
  return "HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters\$GuidLower\DohInterfaceSettings"
}

function Get-InterfaceDohMap([string]$GuidLower) {
  $map = @{}
  $base = Get-DohRegistryBase $GuidLower
  foreach ($sub in 'Doh', 'Doh6') {
    $subPath = Join-Path $base $sub
    if (-not (Test-Path -LiteralPath $subPath -ErrorAction SilentlyContinue)) { continue }
    Get-ChildItem -LiteralPath $subPath -ErrorAction SilentlyContinue | ForEach-Object {
      $props = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
      if ($props -and $null -ne $props.DohFlags) {
        $map[$_.PSChildName] = [pscustomobject]@{
          Flags    = [int64]$props.DohFlags
          Template = [string]$props.DohTemplate
        }
      }
    }
  }
  return $map
}

function Get-DohStatusSummary($Adapter) {
  $activeIps = @($Adapter.IPv4Dns + $Adapter.IPv6Dns | Where-Object { $_ })
  if ($activeIps.Count -eq 0 -or $Adapter.DohMap.Count -eq 0) { return 'Выключен' }
  $matched = @($activeIps | Where-Object { $Adapter.DohMap.ContainsKey($_) -and ($Adapter.DohMap[$_].Flags -band 1) -eq 1 })
  if ($matched.Count -eq 0) { return 'Выключен (есть старые ключи для других IP)' }
  $allAuto = (@($matched | Where-Object { $Adapter.DohMap[$_].Flags -eq 17 }).Count -eq $matched.Count)
  if ($matched.Count -eq $activeIps.Count) {
    if ($allAuto) { return 'Включён (On automatic)' }
    return 'Включён (Вручную)'
  }
  return "Частично ($($matched.Count) из $($activeIps.Count) IP)"
}

function Get-AdapterSnapshot([string]$GuidLower, [string]$Alias, [int]$IfIndex) {
  $v4Path = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$GuidLower"
  $v6Path = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\Interfaces\$GuidLower"
  $v4Reg = Get-ItemProperty -LiteralPath $v4Path -ErrorAction SilentlyContinue
  $v6Reg = Get-ItemProperty -LiteralPath $v6Path -ErrorAction SilentlyContinue

  $v4Static = @()
  if ($v4Reg -and -not [string]::IsNullOrWhiteSpace([string]$v4Reg.NameServer)) {
    $v4Static = @($v4Reg.NameServer -split '[,\s]+' | Where-Object { $_ })
  }
  $v6Static = @()
  if ($v6Reg -and -not [string]::IsNullOrWhiteSpace([string]$v6Reg.NameServer)) {
    $v6Static = @($v6Reg.NameServer -split '[,\s]+' | Where-Object { $_ })
  }

  $dohEntries = @()
  $base = Get-DohRegistryBase $GuidLower
  foreach ($sub in 'Doh', 'Doh6') {
    $subPath = Join-Path $base $sub
    if (-not (Test-Path -LiteralPath $subPath -ErrorAction SilentlyContinue)) { continue }
    Get-ChildItem -LiteralPath $subPath -ErrorAction SilentlyContinue | ForEach-Object {
      $props = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
      $dohEntries += [pscustomobject]@{
        Sub      = $sub
        Ip       = $_.PSChildName
        Template = if ($props -and $props.DohTemplate) { [string]$props.DohTemplate } else { $null }
        Flags    = if ($props -and $null -ne $props.DohFlags) { [int64]$props.DohFlags } else { $null }
      }
    }
  }

  return [pscustomobject]@{
    IfIndex    = $IfIndex
    GuidLower  = $GuidLower
    IPv4Static = $v4Static
    IPv6Static = $v6Static
    DohEntries = $dohEntries
  }
}

function Restore-AdapterSnapshot($Snap, [bool]$IPv6Bound) {
  if ($Snap.IPv4Static.Count -gt 0) {
    Set-DnsClientServerAddress -InterfaceIndex $Snap.IfIndex -ServerAddresses $Snap.IPv4Static -ErrorAction SilentlyContinue
  } else {
    Set-DnsClientServerAddress -InterfaceIndex $Snap.IfIndex -ResetServerAddresses -ErrorAction SilentlyContinue
  }
  if ($IPv6Bound) {
    if ($Snap.IPv6Static.Count -gt 0) {
      Set-DnsClientServerAddress -InterfaceIndex $Snap.IfIndex -ServerAddresses $Snap.IPv6Static -ErrorAction SilentlyContinue
    } else {
      $v6Key = "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\Interfaces\$($Snap.GuidLower)"
      try {
        $reg = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey("SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\Interfaces\$($Snap.GuidLower)", $true)
        if ($reg) { $reg.DeleteValue('NameServer', $false); $reg.Close() }
      } catch { }
    }
  }

  $base = Get-DohRegistryBase $Snap.GuidLower
  if (Test-Path -LiteralPath $base -ErrorAction SilentlyContinue) {
    Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
  }
  foreach ($e in $Snap.DohEntries) {
    $regKey = "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters\$($Snap.GuidLower)\DohInterfaceSettings\$($e.Sub)\$($e.Ip)"
    if ($null -ne $e.Template) {
      [Microsoft.Win32.Registry]::SetValue($regKey, 'DohTemplate', $e.Template, [Microsoft.Win32.RegistryValueKind]::String)
    }
    if ($null -ne $e.Flags) {
      [Microsoft.Win32.Registry]::SetValue($regKey, 'DohFlags', [int64]$e.Flags, [Microsoft.Win32.RegistryValueKind]::QWord)
    }
  }
  Clear-DnsClientCache
}

function Get-ActiveInternetAdapter {
  $adapters = @(Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' })
  if (-not $adapters) { throw 'Не найдено ни одного активного сетевого подключения.' }

  $routes4 = @(Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object RouteMetric)
  $routes6 = @(Get-NetRoute -AddressFamily IPv6 -DestinationPrefix '::/0' -ErrorAction SilentlyContinue | Sort-Object RouteMetric)
  $profiles = @{}
  foreach ($prof in (Get-NetConnectionProfile -ErrorAction SilentlyContinue)) { $profiles[$prof.InterfaceIndex] = $prof }

  $scored = foreach ($a in $adapters) {
    $isPhysical = ($a.HardwareInterface -or $a.InterfaceDescription -notmatch 'Virtual|Hyper-V|VMware|VirtualBox|Loopback|TAP|TUN|WireGuard|Tailscale|ZeroTier|Bluetooth')
    $r4 = $routes4 | Where-Object { $_.InterfaceIndex -eq $a.ifIndex } | Select-Object -First 1
    $r6 = $routes6 | Where-Object { $_.InterfaceIndex -eq $a.ifIndex } | Select-Object -First 1
    $hasGw4 = [bool]$r4
    $hasGw6 = [bool]$r6
    if (-not ($hasGw4 -or $hasGw6)) { continue }

    $prof = $profiles[$a.ifIndex]
    $hasNet = $prof -and ($prof.IPv4Connectivity -eq 'Internet' -or $prof.IPv6Connectivity -eq 'Internet')

    $if4 = Get-NetIPInterface -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1
    $if6 = Get-NetIPInterface -InterfaceIndex $a.ifIndex -AddressFamily IPv6 -ErrorAction SilentlyContinue | Select-Object -First 1
    $routeMetric = if ($r4) { [int]$r4.RouteMetric } elseif ($r6) { [int]$r6.RouteMetric } else { 99999 }
    $ifMetric = if ($r4 -and $if4) { [int]$if4.InterfaceMetric } elseif ($if6) { [int]$if6.InterfaceMetric } else { 9999 }

    [pscustomobject]@{
      Adapter    = $a
      Score      = ([int]$hasNet * 1000) + ([int]$hasGw4 * 500) + ([int]$isPhysical * 200) + ([int]$hasGw6 * 50)
      Metric     = $routeMetric + $ifMetric
      HasIPv6Net = ($hasGw6 -and $prof -and $prof.IPv6Connectivity -eq 'Internet')
      IsPhysical = $isPhysical
    }
  }

  $ranked = @($scored | Sort-Object -Property @{Expression='Score';Descending=$true}, @{Expression='Metric';Descending=$false})
  if ($ranked.Count -eq 0) {
    throw 'Не удалось определить активный интернет-адаптер со шлюзом (Ethernet / Wi-Fi).'
  }
  $best = $ranked[0]
  $otherActive = @($ranked | Select-Object -Skip 1 | Where-Object { $_.IsPhysical } | ForEach-Object { $_.Adapter.Name })

  $a = $best.Adapter
  $guidLower = ([string]$a.InterfaceGuid).ToLowerInvariant()
  $dns4 = @((Get-DnsClientServerAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses)
  $dns6 = @((Get-DnsClientServerAddress -InterfaceIndex $a.ifIndex -AddressFamily IPv6 -ErrorAction SilentlyContinue).ServerAddresses)

  $v4Reg = Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$guidLower" -ErrorAction SilentlyContinue
  $v6Reg = Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters\Interfaces\$guidLower" -ErrorAction SilentlyContinue
  $dhcp4 = @()
  if ($v4Reg -and $v4Reg.DhcpNameServer) {
    $dhcp4 = @($v4Reg.DhcpNameServer -split '[,\s]+' | Where-Object { $_ })
  }
  $static4 = [bool]($v4Reg -and -not [string]::IsNullOrWhiteSpace([string]$v4Reg.NameServer))
  $static6 = [bool]($v6Reg -and -not [string]::IsNullOrWhiteSpace([string]$v6Reg.NameServer))
  $v6Bind = Get-NetAdapterBinding -InterfaceAlias $a.Name -ComponentID 'ms_tcpip6' -ErrorAction SilentlyContinue
  $ipv6Bound = [bool]($v6Bind -and $v6Bind.Enabled)

  return [pscustomobject]@{
    Name          = $a.Name
    Description   = $a.InterfaceDescription
    IfIndex       = $a.ifIndex
    GuidLower     = $guidLower
    IPv4Dns       = $dns4
    IPv6Dns       = $dns6
    Dhcp4Dns      = $dhcp4
    IsStatic      = ($static4 -or $static6)
    IPv6Bound     = $ipv6Bound
    HasIPv6Net    = $best.HasIPv6Net
    OtherAdapters = $otherActive
    DohMap        = (Get-InterfaceDohMap $guidLower)
  }
}

function New-DnsQueryBytes([string]$HostName, [uint16]$Id) {
  $list = New-Object System.Collections.Generic.List[byte]
  $list.Add([byte](($Id -shr 8) -band 0xFF))
  $list.Add([byte]($Id -band 0xFF))
  # Flags: Standard query + RD=1 (0x0100), QDCOUNT=1
  $list.AddRange([byte[]]@(0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00))
  foreach ($part in $HostName.Split('.')) {
    $b = [Text.Encoding]::ASCII.GetBytes($part)
    $list.Add([byte]$b.Length)
    $list.AddRange($b)
  }
  # Root zero, QTYPE=A (1), QCLASS=IN (1)
  $list.AddRange([byte[]]@(0x00, 0x00, 0x01, 0x00, 0x01))
  return $list.ToArray()
}

function Measure-DnsUdpLatency {
  param(
    [string]$ServerIp,
    [string[]]$Domains,
    [int]$TimeoutMs = 1000
  )
  if ([string]::IsNullOrWhiteSpace($ServerIp)) { return $null }
  try {
    $ipObj = [System.Net.IPAddress]::Parse($ServerIp)
  } catch { return $null }

  $anyIp = if ($ipObj.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6) {
    [System.Net.IPAddress]::IPv6Any
  } else {
    [System.Net.IPAddress]::Any
  }

  $times = New-Object System.Collections.Generic.List[double]
  $udp = $null
  $consecutiveTimeouts = 0
  try {
    $udp = New-Object System.Net.Sockets.UdpClient($ipObj.AddressFamily)
    $udp.Client.ReceiveTimeout = $TimeoutMs
    $udp.Client.SendTimeout = $TimeoutMs
    $ep = New-Object System.Net.IPEndPoint($ipObj, 53)

    # Warm up ARP / route once
    try {
      $warm = New-DnsQueryBytes 'example.com' 0x1000
      $null = $udp.Send($warm, $warm.Length, $ep)
      $refEp = New-Object System.Net.IPEndPoint($anyIp, 0)
      $null = $udp.Receive([ref]$refEp)
    } catch { }

    $qid = [uint16]0x2001
    foreach ($d in $Domains) {
      if ($consecutiveTimeouts -ge 2) { break }
      $id = [uint16]$qid; $qid++
      $pkt = New-DnsQueryBytes $d $id
      $sw = [Diagnostics.Stopwatch]::StartNew()
      try {
        $null = $udp.Send($pkt, $pkt.Length, $ep)
        while ($true) {
          $left = $TimeoutMs - [int]$sw.ElapsedMilliseconds
          if ($left -le 0) { throw 'timeout' }
          $udp.Client.ReceiveTimeout = $left
          $refEp = New-Object System.Net.IPEndPoint($anyIp, 0)
          $resp = $udp.Receive([ref]$refEp)
          if ($refEp.Address.Equals($ipObj) -and $resp.Length -ge 12 -and
              $resp[0] -eq (($id -shr 8) -band 0xFF) -and $resp[1] -eq ($id -band 0xFF) -and
              (($resp[2] -band 0x80) -ne 0)) { break }
        }
        $sw.Stop()
        if (($resp[3] -band 0x0F) -eq 0) {
          $times.Add($sw.Elapsed.TotalMilliseconds)
          $consecutiveTimeouts = 0
        }
      } catch {
        $sw.Stop()
        $consecutiveTimeouts++
      }
    }
  } catch {
    return $null
  } finally {
    if ($udp) { $udp.Close() }
  }

  if ($times.Count -eq 0) { return $null }
  $sorted = @($times | Sort-Object)
  return [pscustomobject]@{
    MedianMs = [math]::Round($sorted[[int][math]::Floor($sorted.Count / 2)], 1)
    MinMs    = [math]::Round($sorted[0], 1)
    OkCount  = $times.Count
  }
}

function Test-DoHEndpoint {
  param(
    [string]$ServerIp,
    [string]$Url,
    [int]$TimeoutMs = 2000
  )
  if ([string]::IsNullOrWhiteSpace($ServerIp) -or [string]::IsNullOrWhiteSpace($Url)) { return $null }
  $tcp = $null
  $ssl = $null
  try {
    $ip = [System.Net.IPAddress]::Parse($ServerIp)
    $hostName = ([Uri]$Url).Host
    $tcp = New-Object System.Net.Sockets.TcpClient($ip.AddressFamily)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $iar = $tcp.BeginConnect($ip, 443, $null, $null)
    if (-not $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) { return $null }
    $tcp.EndConnect($iar)
    $sw.Stop()
    $tcpMs = [math]::Round($sw.Elapsed.TotalMilliseconds, 1)

    $ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(), $false)
    $ssl.ReadTimeout = $TimeoutMs
    $ssl.WriteTimeout = $TimeoutMs
    # Connect directly to DNS IP on port 443 while validating TLS cert for the DoH hostname (like Windows Dnscache).
    $certs = New-Object System.Security.Cryptography.X509Certificates.X509CertificateCollection
    $proto = [System.Security.Authentication.SslProtocols]::Tls12
    try { $proto = $proto -bor [System.Security.Authentication.SslProtocols]::Tls13 } catch { }
    $ssl.AuthenticateAsClient($hostName, $certs, $proto, $false)
    return [pscustomobject]@{ TcpMs = $tcpMs; TlsOk = $true }
  } catch {
    return $null
  } finally {
    if ($ssl) { $ssl.Dispose() }
    if ($tcp) { $tcp.Close() }
  }
}

function Test-DoHHttpQuery {
  param(
    [string]$ServerIp,
    [string]$Url,
    [bool]$Http2Only = $false
  )
  $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
  if (-not (Test-Path -LiteralPath $curl -PathType Leaf)) { return $true }
  $hostName = ([Uri]$Url).Host
  $b64 = [Convert]::ToBase64String((New-DnsQueryBytes 'example.com' 0x4242)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
  $sep = if ($Url -match '\?') { '&' } else { '?' }
  $queryUrl = "$Url${sep}dns=$b64"
  $tmp = Join-Path ([IO.Path]::GetTempPath()) ("yaro_doh_{0}.bin" -f [Guid]::NewGuid().ToString('N'))
  try {
    $code = & $curl -sS -m 3 --resolve "${hostName}:443:${ServerIp}" -H 'Accept: application/dns-message' -o $tmp -w '%{http_code}' $queryUrl 2>$null
    if ($code -eq '200' -and (Test-Path -LiteralPath $tmp -PathType Leaf)) {
      $resp = [IO.File]::ReadAllBytes($tmp)
      return ($resp.Length -ge 12 -and $resp[0] -eq 0x42 -and $resp[1] -eq 0x42 -and (($resp[3] -band 0x0F) -eq 0))
    }
    # Built-in Windows curl lacks HTTP/2 support; Quad9 DoH explicitly answers HTTP 505 to HTTP/1.1.
    if ($Http2Only -and $code -eq '505') { return $true }
    return $false
  } catch {
    return $false
  } finally {
    if (Test-Path -LiteralPath $tmp -ErrorAction SilentlyContinue) {
      Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
  }
}

function Get-DnsProviders {
  return @(
    [pscustomobject]@{ Id='quad9'; Name='Quad9 Security'; Filter='Вирусы и фишинг'; BuiltIn=$true; Http2Only=$true;
      IPv4=@('9.9.9.9','149.112.112.112'); IPv6=@('2620:fe::fe','2620:fe::9'); DoH='https://dns.quad9.net/dns-query' },
    [pscustomobject]@{ Id='cloudflare'; Name='Cloudflare Standard'; Filter='Нет фильтрации'; BuiltIn=$true; Http2Only=$false;
      IPv4=@('1.1.1.1','1.0.0.1'); IPv6=@('2606:4700:4700::1111','2606:4700:4700::1001'); DoH='https://cloudflare-dns.com/dns-query' },
    [pscustomobject]@{ Id='cf_malware'; Name='Cloudflare Malware'; Filter='Вирусы и фишинг'; BuiltIn=$false; Http2Only=$false;
      IPv4=@('1.1.1.2','1.0.0.2'); IPv6=@('2606:4700:4700::1112','2606:4700:4700::1002'); DoH='https://security.cloudflare-dns.com/dns-query' },
    [pscustomobject]@{ Id='google'; Name='Google Public DNS'; Filter='Нет фильтрации'; BuiltIn=$true; Http2Only=$false;
      IPv4=@('8.8.8.8','8.8.4.4'); IPv6=@('2001:4860:4860::8888','2001:4860:4860::8844'); DoH='https://dns.google/dns-query' },
    [pscustomobject]@{ Id='adguard'; Name='AdGuard Default'; Filter='Реклама+трекеры+вирусы'; BuiltIn=$false; Http2Only=$false;
      IPv4=@('94.140.14.14','94.140.15.15'); IPv6=@('2a10:50c0::ad1:ff','2a10:50c0::ad2:ff'); DoH='https://dns.adguard-dns.com/dns-query' },
    [pscustomobject]@{ Id='adguard_raw'; Name='AdGuard Unfiltered'; Filter='Нет фильтрации'; BuiltIn=$false; Http2Only=$false;
      IPv4=@('94.140.14.140','94.140.14.141'); IPv6=@('2a10:50c0::1:ff','2a10:50c0::2:ff'); DoH='https://unfiltered.adguard-dns.com/dns-query' },
    [pscustomobject]@{ Id='controld'; Name='Control D Malware'; Filter='Вирусы и фишинг'; BuiltIn=$false; Http2Only=$false;
      IPv4=@('76.76.2.1','76.76.10.1'); IPv6=@('2606:1a40::1','2606:1a40:1::1'); DoH='https://freedns.controld.com/p1' },
    [pscustomobject]@{ Id='opendns'; Name='OpenDNS (Cisco)'; Filter='Базовая защита'; BuiltIn=$false; Http2Only=$false;
      IPv4=@('208.67.222.222','208.67.220.220'); IPv6=@('2620:119:35::35','2620:119:53::53'); DoH='https://doh.opendns.com/dns-query' },
    [pscustomobject]@{ Id='dnssb'; Name='DNS.SB'; Filter='Нет фильтрации'; BuiltIn=$false; Http2Only=$false;
      IPv4=@('185.222.222.222','45.11.45.11'); IPv6=@('2a09::','2a11::'); DoH='https://doh.dns.sb/dns-query' },
    [pscustomobject]@{ Id='cleanbrowsing'; Name='CleanBrowsing Sec'; Filter='Вирусы и фишинг'; BuiltIn=$false; Http2Only=$false;
      IPv4=@('185.228.168.9','185.228.169.9'); IPv6=@('2a0d:2a00:1::2','2a0d:2a00:2::2'); DoH='https://doh.cleanbrowsing.org/doh/security-filter/' }
  )
}

function Apply-DnsSelection {
  param(
    [string]$SelectionId,
    [string]$TargetGuidLower
  )

  # Resolve target adapter directly by GUID first so a brief link drop does not fail elevation.
  $adapter = $null
  if ($TargetGuidLower) {
    $normGuid = $TargetGuidLower.ToLowerInvariant()
    $match = Get-NetAdapter -ErrorAction Stop | Where-Object { ([string]$_.InterfaceGuid).ToLowerInvariant() -eq $normGuid } | Select-Object -First 1
    if (-not $match) { throw "Адаптер $TargetGuidLower не найден." }
    $v6Bind = Get-NetAdapterBinding -InterfaceAlias $match.Name -ComponentID 'ms_tcpip6' -ErrorAction SilentlyContinue
    $adapter = [pscustomobject]@{
      Name      = $match.Name
      IfIndex   = $match.ifIndex
      GuidLower = $normGuid
      IPv6Bound = [bool]($v6Bind -and $v6Bind.Enabled)
    }
  } else {
    $adapter = Get-ActiveInternetAdapter
  }

  $base = Get-DohRegistryBase $adapter.GuidLower

  if ($SelectionId -eq 'dhcp') {
    Write-Host "  Сброс DNS на автоматическое получение (DHCP) для '$($adapter.Name)'..." -ForegroundColor Cyan
    Set-DnsClientServerAddress -InterfaceIndex $adapter.IfIndex -ResetServerAddresses -ErrorAction Stop
    if (Test-Path -LiteralPath $base) {
      Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
    }
    Clear-DnsClientCache
    & ipconfig.exe /flushdns *> $null
    Write-Host '  [OK] Восстановлен автоматический DNS от роутера/провайдера (DHCP).' -ForegroundColor Green
    return
  }

  $provider = Get-DnsProviders | Where-Object { $_.Id -eq $SelectionId } | Select-Object -First 1
  if (-not $provider) { throw "Неизвестный профиль DNS: $SelectionId" }

  Write-Host "  Применение $($provider.Name) на '$($adapter.Name)'..." -ForegroundColor Cyan

  # Save exact pre-change settings for rollback if verification fails.
  $snapshot = Get-AdapterSnapshot -GuidLower $adapter.GuidLower -Alias $adapter.Name -IfIndex $adapter.IfIndex

  try {
    # 1. Verify direct-IP DoH TLS + HTTP before applying changes
    $tlsOk = Test-DoHEndpoint -ServerIp $provider.IPv4[0] -Url $provider.DoH
    $httpOk = Test-DoHHttpQuery -ServerIp $provider.IPv4[0] -Url $provider.DoH -Http2Only $provider.Http2Only
    if (-not $tlsOk -or -not $httpOk) {
      throw "Сервер $($provider.IPv4[0]) не прошёл прямую проверку HTTPS/TLS для DoH ($($provider.DoH))."
    }

    # 2. Register DoH template globally for custom providers if Windows does not know the IP yet
    $allIps = @($provider.IPv4)
    if ($adapter.IPv6Bound) { $allIps += $provider.IPv6 }
    foreach ($ip in $allIps) {
      $existing = Get-DnsClientDohServerAddress -ServerAddress $ip -ErrorAction SilentlyContinue
      if (-not $existing) {
        Add-DnsClientDohServerAddress -ServerAddress $ip -DohTemplate $provider.DoH -AllowFallbackToUdp $true -AutoUpgrade $true -ErrorAction Stop | Out-Null
      }
    }

    # 3. Apply IPv4 + IPv6 DNS server addresses
    Set-DnsClientServerAddress -InterfaceIndex $adapter.IfIndex -ServerAddresses $provider.IPv4 -ErrorAction Stop
    if ($adapter.IPv6Bound) {
      Set-DnsClientServerAddress -InterfaceIndex $adapter.IfIndex -ServerAddresses $provider.IPv6 -ErrorAction Stop
    }

    # 4. Apply per-interface DoH ("On (automatic template)" -> QWord DohFlags = 17, plus DohTemplate)
    foreach ($sub in 'Doh', 'Doh6') {
      $subPath = Join-Path $base $sub
      if (Test-Path -LiteralPath $subPath) {
        Remove-Item -LiteralPath $subPath -Recurse -Force -ErrorAction SilentlyContinue
      }
    }
    foreach ($ip in $provider.IPv4) {
      $regKey = "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters\$($adapter.GuidLower)\DohInterfaceSettings\Doh\$ip"
      [Microsoft.Win32.Registry]::SetValue($regKey, 'DohTemplate', $provider.DoH, [Microsoft.Win32.RegistryValueKind]::String)
      [Microsoft.Win32.Registry]::SetValue($regKey, 'DohFlags', [int64]17, [Microsoft.Win32.RegistryValueKind]::QWord)
    }
    if ($adapter.IPv6Bound) {
      foreach ($ip in $provider.IPv6) {
        $regKey = "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters\$($adapter.GuidLower)\DohInterfaceSettings\Doh6\$ip"
        [Microsoft.Win32.Registry]::SetValue($regKey, 'DohTemplate', $provider.DoH, [Microsoft.Win32.RegistryValueKind]::String)
        [Microsoft.Win32.Registry]::SetValue($regKey, 'DohFlags', [int64]17, [Microsoft.Win32.RegistryValueKind]::QWord)
      }
    }

    Clear-DnsClientCache
    & ipconfig.exe /flushdns *> $null

    # 5. Verify saved settings and live system resolution
    $cur4 = @((Get-DnsClientServerAddress -InterfaceIndex $adapter.IfIndex -AddressFamily IPv4 -ErrorAction Stop).ServerAddresses)
    $cur6 = @((Get-DnsClientServerAddress -InterfaceIndex $adapter.IfIndex -AddressFamily IPv6 -ErrorAction SilentlyContinue).ServerAddresses)
    $dohMap = Get-InterfaceDohMap $adapter.GuidLower
    $missingDoh = @($allIps | Where-Object { -not $dohMap.ContainsKey($_) -or $dohMap[$_].Flags -ne 17 })
    if ($missingDoh.Count -gt 0) {
      throw "Не удалось подтвердить DoH для адресов: $($missingDoh -join ', ')"
    }
    $resolved = Resolve-DnsName -Name 'example.com' -Type A -ErrorAction Stop
    if (-not $resolved) { throw 'Системный DNS-резолв не вернул ответ.' }

    Write-Host "  [OK] IPv4 DNS : $($cur4 -join ', ')" -ForegroundColor Green
    if ($adapter.IPv6Bound) {
      Write-Host "  [OK] IPv6 DNS : $($cur6 -join ', ')" -ForegroundColor Green
    } else {
      Write-Host '  [i]  IPv6 отключён на адаптере — применены только IPv4 адреса.' -ForegroundColor DarkGray
    }
    Write-Host "  [OK] DoH      : On (automatic template) -> $($provider.DoH) (HTTPS/TLS подтверждён)" -ForegroundColor Green
    Write-Host '  [OK] Проверка : системный DNS-резолв работает штатно.' -ForegroundColor Green
  } catch {
    Write-Host "  [!] Ошибка проверки — выполняю откат к прежним настройкам DNS..." -ForegroundColor Yellow
    Restore-AdapterSnapshot -Snap $snapshot -IPv6Bound $adapter.IPv6Bound
    throw
  }
}

# Handle elevated child execution directly
if ($ApplyId) {
  try {
    Apply-DnsSelection -SelectionId $ApplyId -TargetGuidLower $AdapterGuid
    Pause-IfInteractive 'Готово. Нажмите Enter для закрытия окна...'
    exit 0
  } catch {
    Write-Host ''
    Write-Host "  [ОШИБКА] $($_.Exception.Message)" -ForegroundColor Red
    Pause-IfInteractive
    exit 1
  }
}

# ---------------- Interactive / Benchmark Mode ----------------
try {
  $adapter = Get-ActiveInternetAdapter
} catch {
  Write-Host "[ОШИБКА] $($_.Exception.Message)" -ForegroundColor Red
  Pause-IfInteractive
  exit 1
}

$dohStatusText = Get-DohStatusSummary $adapter

Write-Host ''
Write-Host '============================================================================' -ForegroundColor Cyan
Write-Host '  YARO — ЗАМЕР СКОРОСТИ DNS И НАСТРОЙКА DoH (IPv4 + IPv6)' -ForegroundColor White
Write-Host '============================================================================' -ForegroundColor Cyan
Write-Host "  Адаптер         : $($adapter.Name) ($($adapter.Description))"
Write-Host "  Текущий IPv4 DNS: $(if ($adapter.IPv4Dns) { $adapter.IPv4Dns -join ', ' } else { 'Нет' }) $(if ($adapter.IsStatic) { '[Вручную]' } else { '[DHCP / Родной]' })"
Write-Host "  Текущий IPv6 DNS: $(if ($adapter.IPv6Dns) { $adapter.IPv6Dns -join ', ' } else { 'Нет' })"
if ($adapter.Dhcp4Dns.Count -gt 0) {
  Write-Host "  Родной от DHCP  : $($adapter.Dhcp4Dns -join ', ')"
}
Write-Host "  DoH на адаптере : $dohStatusText"
Write-Host "  Интернет IPv6   : $(if ($adapter.HasIPv6Net) { 'Активен (будет замерен)' } else { 'Нет маршрута IPv6 (замер только по IPv4)' })"
if ($adapter.OtherAdapters.Count -gt 0) {
  Write-Host ("  [i] Ещё активны : {0} (настройки меняются только для '{1}')" -f ($adapter.OtherAdapters -join ', '), $adapter.Name) -ForegroundColor DarkGray
}
Write-Host '----------------------------------------------------------------------------' -ForegroundColor DarkGray
Write-Host '  Идёт замер задержек (по 5 реальным доменам + прямой TLS DoH на IP:443)...'
Write-Host ''

$domains = @('google.com', 'cloudflare.com', 'github.com', 'steampowered.com', 'wikipedia.org')
$providers = Get-DnsProviders
$rows = New-Object System.Collections.Generic.List[object]

# Always benchmark the native ISP / DHCP router IP
$nativeIp4 = if ($adapter.Dhcp4Dns.Count -gt 0) { $adapter.Dhcp4Dns[0] } elseif (-not $adapter.IsStatic -and $adapter.IPv4Dns.Count -gt 0) { $adapter.IPv4Dns[0] } else { $null }
if ($nativeIp4) {
  Write-Host -NoNewline ("  Проверяю: {0,-24}`r" -f 'Родной (Роутер / DHCP)')
  $u4 = Measure-DnsUdpLatency -ServerIp $nativeIp4 -Domains $domains
  $rows.Add([pscustomobject]@{
    Index     = 0
    Id        = 'dhcp'
    IsNative  = $true
    IsCurrent = (-not $adapter.IsStatic)
    Name      = 'Родной (Роутер / DHCP)'
    IPv4      = $nativeIp4
    Udp4Med   = if ($u4) { $u4.MedianMs } else { 9999.0 }
    Udp4Min   = if ($u4) { $u4.MinMs } else { 9999.0 }
    Udp6Med   = $null
    DohMs     = $null
    Filter    = 'Нет шифрования DoH'
    Provider  = $null
  })
}

$idx = 1
foreach ($p in $providers) {
  Write-Host -NoNewline ("  Проверяю: {0,-24}`r" -f $p.Name)
  $u4 = Measure-DnsUdpLatency -ServerIp $p.IPv4[0] -Domains $domains
  $u6 = if ($adapter.HasIPv6Net) { Measure-DnsUdpLatency -ServerIp $p.IPv6[0] -Domains $domains } else { $null }
  $doh = Test-DoHEndpoint -ServerIp $p.IPv4[0] -Url $p.DoH
  $isCur = ($adapter.IsStatic -and $adapter.IPv4Dns.Count -gt 0 -and ($adapter.IPv4Dns[0] -eq $p.IPv4[0]))

  $rows.Add([pscustomobject]@{
    Index     = $idx
    Id        = $p.Id
    IsNative  = $false
    IsCurrent = $isCur
    Name      = $p.Name
    IPv4      = $p.IPv4[0]
    Udp4Med   = if ($u4) { $u4.MedianMs } else { 9999.0 }
    Udp4Min   = if ($u4) { $u4.MinMs } else { 9999.0 }
    Udp6Med   = if ($u6) { $u6.MedianMs } else { $null }
    DohMs     = if ($doh) { $doh.TcpMs } else { $null }
    Filter    = $p.Filter
    Provider  = $p
  })
  $idx++
}
Write-Host ("{0,-48}" -f ' ')

$sorted = @($rows | Sort-Object -Property `
  @{Expression={ $_.Udp4Med }; Descending=$false}, `
  @{Expression={ if ($null -ne $_.DohMs) { $_.DohMs } else { 9999.0 } }; Descending=$false}, `
  @{Expression={ if ($_.Provider -and $_.Provider.BuiltIn) { 0 } else { 1 } }; Descending=$false})

# Print clean aligned results table
Write-Host ('  {0,-4} {1,-23} {2,-16} {3,9} {4,8} {5,8} {6,-22}' -f '#', 'Сервер', 'IPv4', 'IPv4 ms', 'IPv6 ms', 'DoH 443', 'Фильтрация') -ForegroundColor Yellow
Write-Host ('  ' + ('-' * 97)) -ForegroundColor DarkGray

$numberedChoices = @{}
$menuNum = 1
foreach ($r in $sorted) {
  $tag = if ($r.IsNative) { 'DHCP' } else { [string]$menuNum; $numberedChoices[[string]$menuNum] = $r; $menuNum++ }
  $v4Str = if ($r.Udp4Med -lt 9999) { ('{0:N1} ms' -f $r.Udp4Med) } else { 'таймаут' }
  $v6Str = if ($null -ne $r.Udp6Med) { ('{0:N1} ms' -f $r.Udp6Med) } elseif ($adapter.HasIPv6Net -and -not $r.IsNative) { 'таймаут' } else { '-' }
  $dohStr = if ($null -ne $r.DohMs) { ('{0:N1} ms' -f $r.DohMs) } else { '-' }
  $dispName = $r.Name + $(if ($r.IsCurrent) { ' [*]' } else { '' })
  $color = if ($r.IsCurrent) { 'Cyan' } elseif ($r.IsNative) { 'Gray' } else { 'White' }
  Write-Host ('  {0,-4} {1,-23} {2,-16} {3,9} {4,8} {5,8} {6,-22}' -f $tag, $dispName, $r.IPv4, $v4Str, $v6Str, $dohStr, $r.Filter) -ForegroundColor $color
}

$winner = $sorted | Where-Object { -not $_.IsNative -and $_.Udp4Med -lt 9999 -and $null -ne $_.DohMs } | Select-Object -First 1
if (-not $winner) {
  $winner = $sorted | Where-Object { -not $_.IsNative -and $_.Udp4Med -lt 9999 } | Select-Object -First 1
}

Write-Host ''
Write-Host '============================================================================' -ForegroundColor Cyan
if (-not $winner) {
  Write-Host '  [!] Не удалось измерить внешние DNS-серверы. Проверьте подключение к сети.' -ForegroundColor Red
  Pause-IfInteractive
  exit 1
}

$wp = $winner.Provider
$nativeRow = $sorted | Where-Object { $_.IsNative } | Select-Object -First 1
if ($nativeRow -and $nativeRow.Udp4Med -lt 9999) {
  $cacheNote = if ($nativeRow.Udp4Med -lt 4.0) { 'локальный кэш роутера, без DoH' } else { 'без DoH' }
  Write-Host ("  Родной DNS ({0}) : {1:N1} ms  ({2})" -f $nativeRow.IPv4, $nativeRow.Udp4Med, $cacheNote)
}
Write-Host ("  Самый быстрый с DoH  : {0} — {1:N1} ms ({2})" -f $wp.Name, $winner.Udp4Med, $wp.Filter) -ForegroundColor Green
Write-Host ("    IPv4 : {0}" -f ($wp.IPv4 -join ', '))
Write-Host ("    IPv6 : {0}" -f ($wp.IPv6 -join ', '))
Write-Host ("    DoH  : {0}  [On (automatic)]" -f $wp.DoH)
if ($winner.IsCurrent -and $dohStatusText -like 'Включён*') {
  Write-Host '  [i] Этот быстрый DNS и DoH уже активны на вашем адаптере.' -ForegroundColor Cyan
}
Write-Host '============================================================================' -ForegroundColor Cyan

if ($CheckOnly) {
  exit 0
}

Write-Host ''
Write-Host "  Сменить DNS на самый быстрый ($($wp.Name)) + включить DoH автоматически?" -ForegroundColor White
Write-Host '  [Д / Y] Да   |   [Н / N] Нет (выйти)   |   [1-10] Выбрать другой   |   [0] Сбросить на авто (DHCP)' -ForegroundColor Gray
Write-Host '  (Подсказка: следите за раскладкой — латинская Y и русская Н на одной клавише!)' -ForegroundColor DarkGray
$choice = (Read-Host '  Ваш выбор').Trim()

$selectedId = $null
if ($choice -match '^(?i:y|yes|д|да)$') {
  $selectedId = $wp.Id
} elseif ($choice -eq '0') {
  $selectedId = 'dhcp'
} elseif ($numberedChoices.ContainsKey($choice)) {
  $selectedId = $numberedChoices[$choice].Id
} else {
  Write-Host ''
  Write-Host '  Отменено. Настройки сети НЕ изменены.' -ForegroundColor Yellow
  Pause-IfInteractive
  exit 0
}

Write-Host ''
if (Test-IsAdmin) {
  try {
    Apply-DnsSelection -SelectionId $selectedId -TargetGuidLower $adapter.GuidLower
    Pause-IfInteractive 'Готово. Нажмите Enter для выхода...'
    exit 0
  } catch {
    Write-Host "  [ОШИБКА] $($_.Exception.Message)" -ForegroundColor Red
    Pause-IfInteractive
    exit 1
  }
} else {
  Write-Host '  Запрос прав администратора (UAC) для применения настроек...' -ForegroundColor Yellow
  $selfPath = $env:YARO_SELF
  if (-not $selfPath -or -not (Test-Path -LiteralPath $selfPath -PathType Leaf)) {
    Write-Host '  [ОШИБКА] Не найден путь к Yaro-DNS.cmd для перезапуска с правами администратора.' -ForegroundColor Red
    Pause-IfInteractive
    exit 1
  }
  $selfEsc = [Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent($selfPath)
  $idEsc   = [Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent($selectedId)
  $guidEsc = [Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent($adapter.GuidLower)
  $psExe   = Join-Path $PSHOME 'powershell.exe'
  $childScript = @"
`$env:YARO_SELF = '$selfEsc'
`$bytes = [IO.File]::ReadAllBytes(`$env:YARO_SELF)
`$h = ([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash(`$bytes))) -replace '-'
if (`$h -ne '$($script:SelfHash)') { Write-Host '  [ОШИБКА] Файл скрипта изменился после запуска. Отмена.' -ForegroundColor Red; `$null = Read-Host 'Нажмите Enter...'; exit 2 }
`$c = ([Text.Encoding]::UTF8.GetString(`$bytes) -split '(?m)^:: __YARO_PS_START__\r?`$', 2)[1]
& ([scriptblock]::Create(`$c)) -ApplyId '$idEsc' -AdapterGuid '$guidEsc'
"@
  $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childScript))
  try {
    $proc = Start-Process -FilePath $psExe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded" -Verb RunAs -Wait -PassThru -ErrorAction Stop
    exit $proc.ExitCode
  } catch {
    Write-Host "  [ОШИБКА] Не удалось получить права администратора: $($_.Exception.Message)" -ForegroundColor Red
    Pause-IfInteractive
    exit 1
  }
}
