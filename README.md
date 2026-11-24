<p align="center"><img src="assets/yaro-banner.png" alt="Yaro — Windows 11, distilled" width="100%"></p>

# Yaro — lean Windows 11 from the official ISO

**English** | [Русский](README.ru.md)

Yaro turns a clean install of the **official** Windows 11 into a lean, quiet and fast system:
no ads and pre-installed junk apps, minimal telemetry, fewer background services, tuned for
games and development (Python, WSL2, Docker).

This repository contains **no Windows files**. You download Windows from Microsoft; Yaro is just
an answer file (`autounattend.xml`) and PowerShell scripts that apply the changes during setup.

> [!WARNING]
> By default Yaro **turns off Microsoft Defender, SmartScreen, UAC prompts, automatic updates,
> printing, Bluetooth headset microphone and the built-in VPN** and switches to the
> *Ultimate Performance* power plan (shorter battery life on laptops). Read
> [What Yaro turns off](#what-yaro-turns-off) and [Options](#options) before installing.
> Try it in a virtual machine first. Use at your own risk.

## Files

| File | What it is |
|---|---|
| `autounattend.xml` | Answer file for a clean install. The scripts are embedded inside it. |
| `Yaro-Apply.cmd` | Applies Yaro to an already installed Windows 11. |
| `scripts/Specialize.ps1` | System-wide changes: apps, components, services, registry. |
| `scripts/FirstLogon.ps1` | Settings of the user and power plan. |
| `scripts/YaroCommon.ps1` | Options and registry helpers shared by both setup stages. |
| `scripts/SetWallpaper.ps1` | Puts the Yaro wallpaper on the desktop. |
| `assets/` | Banner, logo, GitHub social preview and 1920×1080 notebook-paper wallpapers: light (white, cream, yellow, grid, realistic paper) and dark (night sky, plum, ocean, forest, cocoa, navy, graphite, black grid, realistic black paper). |

## Clean install (recommended)

1. **Download Windows 11** from [microsoft.com/software-download/windows11](https://www.microsoft.com/software-download/windows11):
   *Download Windows 11 Disk Image (ISO) for x64 devices*, language **English (United States)**.
   For another language, replace `en-US` with its code (for example `ru-RU`) in the
   `UILanguage`, `SystemLocale` and `UserLocale` lines of `autounattend.xml`.
2. **Optional:** open `autounattend.xml` in Notepad and change
   - `<TimeZone>FLE Standard Time</TimeZone>` — the time zone (Kyiv, Sofia by default); others:
     `Russian Standard Time` (Moscow), `Central European Standard Time` (Warsaw), `UTC`;
   - `<Name>User</Name>` — the name of the local account;
   - the [Options](#options) (search for `Yaro options`).
3. **Make a USB stick** (8 GB or more) with [Rufus](https://rufus.ie): partition scheme **GPT**,
   target system **UEFI**. When Rufus shows the *Windows User Experience* window, **untick
   everything**. Then copy `autounattend.xml` to the **root** of the USB stick.
4. **Boot from the USB stick.** The only question is which disk/partition to install to —
   choose carefully, the formatted partition is erased. Everything else is automatic,
   the PC restarts several times.
5. **After the first sign-in**
   - install drivers (chipset, graphics, Wi-Fi) from the manufacturer's site — Yaro turns off
     driver downloads through Windows Update, so keep the Wi-Fi/LAN driver on the USB stick;
   - check the logs in `%SystemRoot%\Setup\Scripts\Yaro\` — lines with `FAIL` show what did not apply;
   - after installing Intel drivers you can run `Yaro-Apply.cmd` once more: it removes the
     Intel telemetry that Intel software installs;
   - if you want Defender off: turn off **Tamper Protection** (Windows Security › Virus & threat
     protection › Manage settings) and run `Yaro-Apply.cmd`.
6. **Activate Windows with your own key:** Settings › System › Activation › Change product key.
   The key in `autounattend.xml` is Microsoft's generic *install* key: it only selects the
   **Pro** edition and does not activate. For a Home license, replace it with the generic
   Home key `YTMG3-N6DKC-DKB77-7M9GH-8HVX7`.

## Apply to an installed Windows

1. *Code › Download ZIP*, unpack the archive.
2. If you want Defender off, first turn off **Tamper Protection**
   (Windows Security › Virus & threat protection › Manage settings).
3. Run `Yaro-Apply.cmd` from the account you want to configure. Approve elevation for the
   system settings and restore point. The launcher applies desktop and app settings as the original
   user, including when another administrator supplies the credentials.
   If System Protection is off, Yaro cannot create a restore point and asks whether to continue
   without one (to turn it on: Win+R › `SystemPropertiesProtection` › drive C: › Configure).
4. Restart Windows.

## Options

Edit the `Yaro options` block inside `autounattend.xml` for a clean install or
`scripts/YaroCommon.ps1` for `Yaro-Apply.cmd`. `$true` applies the Yaro setting and
`$false` skips it on that run.

| Option | What `$true` does |
|---|---|
| `$DisableDefender` | Turns off Microsoft Defender antivirus and hides its tray icon. While **Tamper Protection** is on (the default on current Windows, also right after setup), Defender ignores these settings — turn it off and run `Yaro-Apply.cmd` |
| `$DisableSmartScreen` | Turns off SmartScreen for downloaded files and apps |
| `$SilentUAC` | Programs get administrator rights without a confirmation window |
| `$PauseUpdates` | No automatic updates, updates paused until 2077 |
| `$DisablePrinting` | Turns off the print spooler |
| `$DisableBtHandsFree` | Turns off the Bluetooth hands-free profile: headphones stay in stereo in games, their microphone is not used |
| `$DisableVPN` | Turns off RasMan/RasAuto (the built-in Windows VPN and dial-up) |
| `$ArgonPerformance` | Performance tweaks from the Argon build: *Ultimate Performance* plan with a 5% minimum CPU state (plugged in and on battery), no power throttling of background processes, `SystemResponsiveness = 0`, no 8.3 short names, Game Mode off. Laptop batteries last less |
| `$ForceMSI` | `$false` by default. Turns on MSI interrupts for the graphics card, NVMe and network adapters, as in Argon. On an unsuitable device the driver can stop working — turn it on only if you know why. Run `Yaro-Apply.cmd` again after installing the graphics driver |
| `$SetWallpaper` | Sets the cream notebook-paper Yaro wallpaper for every user. The image is embedded in `autounattend.xml` and saved to `%SystemRoot%\Web\Wallpaper\Yaro\`; you can change it any time in Settings › Personalization |

## What Yaro changes

### What Yaro turns off
- Microsoft Defender, SmartScreen, Smart App Control, UAC prompts *(options)*.
- Memory integrity / VBS (core isolation), automatic BitLocker device encryption.
- Automatic Windows Update and driver downloads through Windows Update.
- Printing, Bluetooth hands-free, built-in VPN *(options)*, incoming Remote Desktop.
- Location, telemetry, activity history, advertising and suggested apps, Copilot, widgets,
  Bing in Start search, OneDrive sync, Game Bar and game recording, PowerShell and .NET CLI telemetry.

### Removed apps
Xbox app and Game Bar, Copilot, Bing Search, Widgets, Maps, Sticky Notes, Family, Movies & TV,
Camera, Alarms & Clock, Tips, Phone Link, Teams, Clipchamp, Power Automate, Dev Home,
Feedback Hub, Solitaire, News, Weather, Cross Device, Edge Game Assist, Cortana, Office hub,
new Outlook, To Do, People, Get Help, Sound Recorder, Quick Assist, old Intel Graphics panel.
**Kept:** Microsoft Store, App Installer (winget), Terminal, Notepad, Paint, Calculator,
Snipping Tool, Photos, Media Player, Edge, media codecs. Anything removed can be installed again
from the Store.

### Removed components
Windows Hello face, Internet Explorer mode, Steps Recorder, Math Recognizer, legacy Windows Media
Player, handwriting and speech recognition, Fax and Scan, extra wallpapers. Turned off: SMB1,
PowerShell 2.0, XPS printing, Work Folders, Remote Differential Compression, legacy media
playback. On Windows versions that offer .NET Framework 3.5 as an optional feature, Yaro enables
it from connected installation media after matching the package architecture and servicing build. On versions with a standalone installer, install
it separately if an app requires it. [Microsoft .NET 3.5 guidance](https://learn.microsoft.com/en-us/dotnet/framework/install/dotnet-35-windows-11)

### Services
Disabled: DiagTrack, dmwappushservice, MapsBroker, RetailDemo, CDPSvc, CDPUserSvc, TermService,
WSAIFabricSvc, PcaSvc, InventorySvc, TrkWks (+ Spooler, PrintNotify, BTAGService, RasMan, RasAuto,
Defender services when the options are on). Manual: WerSvc, Xbox services, RmSvc.
Automatic: SysMain, DPS. Yaro also skips creating the disabled CDPUserSvc instance at sign-in
when the standard service template is present. Background compatibility, CEIP, disk diagnostic and WinSAT
scheduled tasks are disabled. Yaro also disables the matching OneDrive reporting task when sync
is blocked and the administrator has left health reports off. Under those conditions Yaro also
removes the standard OneDrive startup entries from the current and default profiles as applicable,
unless administrator policy requires autostart. The updater uses a separate task.

### Performance
- Service host grouping (fewer `svchost.exe` processes), memory compression on.
- Kernel kept in RAM, reserved storage off.
- NTFS last-access updates off, long paths (> 260 characters) allowed.
- Hardware-accelerated GPU scheduling. Windowed-game optimizations and variable refresh rate
  are enabled when their settings are missing. Existing graphics choices are preserved.
- Game Bar background recording of recent gameplay is off for the current and new profiles.
- **Argon tweaks** (`$ArgonPerformance`): *Ultimate Performance* plan with a 5% minimum CPU state
  plugged in and on battery, no power throttling of background processes, full CPU priority for
  foreground apps (`SystemResponsiveness = 0`), no 8.3 short names, Game Mode off.
  With `$ArgonPerformance = $false` Yaro keeps the Balanced plan and selects *Best Performance*
  when plugged in.
- MSI interrupt mode for the graphics card, NVMe and network only with the `$ForceMSI` option.
- No network throttling for multimedia, Edge does not preload in the background.
- Installers and drivers do not hang for 2 minutes on certificate checks
  (short certificate download timeouts).

### Interface
Dark theme, Windows 10 context menu, *Open in Notepad* for every file, *End task* on the taskbar,
no Search/Task view/Chat/Copilot buttons, instant menus, folders open in a separate process,
English interface with English and Russian keyboards, developer mode on, Yaro wallpaper on the desktop.

### Setup
Hardware checks (TPM, Secure Boot, CPU, RAM, storage) are skipped. No EULA, network, Microsoft
account and privacy screens; one local administrator `User` without a password; random computer name.

## How to undo common changes

Run in **Command Prompt as administrator**, then restart Windows.

| What | Command |
|---|---|
| Printing | `sc config Spooler start= auto` and `sc config PrintNotify start= demand` |
| Bluetooth headset microphone | `sc config BTAGService start= demand` |
| Built-in VPN | `sc config RasMan start= demand` and `sc config RasAuto start= demand` |
| UAC prompts | `reg add HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System /v ConsentPromptBehaviorAdmin /t REG_DWORD /d 5 /f` |
| Automatic updates | `reg delete HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU /v NoAutoUpdate /f`, then Settings › Windows Update › *Resume updates* |
| Windows 11 context menu | `reg delete "HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}" /f` |
| Normal power plan | `powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e` (Balanced) |
| Game Mode | Settings › Gaming › Game Mode |
| Removed apps | Install them from Microsoft Store |

Defender and SmartScreen are best kept by setting `$DisableDefender = $false` /
`$DisableSmartScreen = $false` **before** installing.

If you restore OneDrive sync after applying Yaro, the reporting task can be enabled
in Task Scheduler. Open OneDrive and turn on startup in its settings. In a new profile, run the
Windows OneDrive installer if needed.

## Troubleshooting

- **"Windows could not parse or process the unattend answer file"** — the file was damaged while
  editing. Download it again and repeat only the changes you need.
- **Setup stops with a language error** — the ISO language does not match `en-US` in the file
  (see step 1).
- **No internet after install** — install the network driver from the manufacturer's site.
- **Something was not applied** — look for `FAIL` in `%SystemRoot%\Setup\Scripts\Yaro\Specialize.log`
  and the user log. On an installed system the user log is `%LOCALAPPDATA%\Yaro\FirstLogon.log`.
  After a clean install both logs are in the system directory.

## Wallpapers

Notebook-paper wallpapers, 1920×1080. Click a preview to open the full image, then save it.

**Light**

<table>
<tr>
<td align="center"><a href="assets/yaro-wallpaper-paper-real.png"><img src="assets/yaro-wallpaper-paper-real.png" width="280" alt="realistic paper"></a><br><sub>realistic paper</sub></td>
<td align="center"><a href="assets/yaro-wallpaper-white.png"><img src="assets/yaro-wallpaper-white.png" width="280" alt="white"></a><br><sub>white</sub></td>
<td align="center"><a href="assets/yaro-wallpaper-cream.png"><img src="assets/yaro-wallpaper-cream.png" width="280" alt="cream"></a><br><sub>cream</sub></td>
</tr>
<tr>
<td align="center"><a href="assets/yaro-wallpaper-yellow.png"><img src="assets/yaro-wallpaper-yellow.png" width="280" alt="yellow"></a><br><sub>yellow</sub></td>
<td align="center"><a href="assets/yaro-wallpaper-grid.png"><img src="assets/yaro-wallpaper-grid.png" width="280" alt="grid"></a><br><sub>grid</sub></td>
<td></td>
</tr>
</table>

**Dark**

<table>
<tr>
<td align="center"><a href="assets/yaro-wallpaper-dark-night.png"><img src="assets/yaro-wallpaper-dark-night.png" width="280" alt="night sky"></a><br><sub>night sky</sub></td>
<td align="center"><a href="assets/yaro-wallpaper-dark-plum.png"><img src="assets/yaro-wallpaper-dark-plum.png" width="280" alt="plum"></a><br><sub>plum</sub></td>
<td align="center"><a href="assets/yaro-wallpaper-dark-ocean.png"><img src="assets/yaro-wallpaper-dark-ocean.png" width="280" alt="ocean"></a><br><sub>ocean</sub></td>
</tr>
<tr>
<td align="center"><a href="assets/yaro-wallpaper-dark-forest.png"><img src="assets/yaro-wallpaper-dark-forest.png" width="280" alt="forest"></a><br><sub>forest</sub></td>
<td align="center"><a href="assets/yaro-wallpaper-dark-cocoa.png"><img src="assets/yaro-wallpaper-dark-cocoa.png" width="280" alt="cocoa"></a><br><sub>cocoa</sub></td>
<td align="center"><a href="assets/yaro-wallpaper-dark-paper-real.png"><img src="assets/yaro-wallpaper-dark-paper-real.png" width="280" alt="realistic black paper"></a><br><sub>realistic black paper</sub></td>
</tr>
<tr>
<td align="center"><a href="assets/yaro-wallpaper-dark-navy.png"><img src="assets/yaro-wallpaper-dark-navy.png" width="280" alt="navy"></a><br><sub>navy</sub></td>
<td align="center"><a href="assets/yaro-wallpaper-dark-graphite.png"><img src="assets/yaro-wallpaper-dark-graphite.png" width="280" alt="graphite"></a><br><sub>graphite</sub></td>
<td align="center"><a href="assets/yaro-wallpaper-dark-grid.png"><img src="assets/yaro-wallpaper-dark-grid.png" width="280" alt="black grid"></a><br><sub>black grid</sub></td>
</tr>
</table>

## Notes

- Yaro grew out of the author's own Windows 11 build used daily on a laptop with Intel Core
  i7-9750H and GeForce RTX 2060. The answer-file version for the official ISO is new —
  test it in a virtual machine (Hyper-V, VirtualBox) before your main PC.
- Not affiliated with Microsoft. Windows is a trademark of Microsoft Corporation.
  This repository contains no Microsoft software and no activation tools.
- License: [MIT](LICENSE).
