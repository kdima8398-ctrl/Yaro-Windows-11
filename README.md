<p align="center"><img src="assets/yaro-banner.png" alt="Yaro — Windows 11, distilled" width="100%"></p>

# Yaro — lean Windows 11 from the official ISO

**English** | [Русский](README.ru.md)

Yaro transforms a clean installation of the **official** Windows 11 into a lean, quiet, and blazing fast system:
free of ads and pre-installed bloatware, with minimal telemetry and background overhead, tuned for
peak gaming performance and a seamless developer workflow (Python, WSL2, Docker).

This repository contains **no pirated Windows files**. You download Windows directly from Microsoft's servers; Yaro is an automated answer file (`autounattend.xml`) and curated scripts that optimize the OS during and after setup.

> [!WARNING]
> By default Yaro **disables Microsoft Defender, SmartScreen, UAC prompts, automatic updates,
> print spooler, Bluetooth headset hands-free mic and built-in VPN** and activates the
> *Ultimate Performance* power plan (faster battery drain on laptops). Read
> [What Yaro changes](#detailed-optimizations-breakdown) and [Options](#configuration-and-options-yaro-options) before installing.
> Try it in a virtual machine first. Use at your own risk.

---

## Repository Files

| File | Description |
|---|---|
| `autounattend.xml` | Primary answer file for fully unattended clean install from a USB stick. |
| `Yaro-Remove-Defender-WIM.cmd` | **Automated offline Defender disabler** directly in `install.wim` BEFORE setup (system files stay intact). |
| `Yaro-Apply.cmd` | Applies Yaro debloat and optimizations to an existing, already installed Windows 11. |
| `Yaro-DNS.cmd` | **(Optional)** Benchmarks latency to popular DNS providers and your router/ISP DNS, identifies the fastest one, and configures IPv4 + IPv6 + encrypted DoH (`On automatic`) if you confirm. |
| `scripts/Remove-Defender-Live.cmd` | Step-by-step Defender disabler on an active, running Windows system. |
| `scripts/Specialize.ps1` | System phase: removes UWP bloatware, tunes services, optimizes registry and networking. |
| `scripts/FirstLogon.ps1` | User phase: instantaneous UI responsiveness, File Explorer tweaks, Ultimate Performance plan. |
| `scripts/YaroCommon.ps1` | Configuration switches (`$true` / `$false`) shared by both setup stages. |
| `scripts/SetWallpaper.ps1` | Sets the signature minimalist Yaro wallpaper on the desktop. |
| `assets/` | Banners, logos, and 1920×1080 notebook-paper wallpapers (light and dark themes). |

---

## Step-by-Step Clean Installation Guide (Recommended)

Setup takes around 10–15 minutes and is completely automated.

### Step 1. Download official Windows 11 ISO
1. Go to Microsoft's official download page: [microsoft.com/software-download/windows11](https://www.microsoft.com/software-download/windows11).
2. Under **"Download Windows 11 Disk Image (ISO) for x64 devices"**, select your edition and language (**English (United States)** or your preferred language).
3. Download the official `.iso` file.

### Step 2. Flash USB drive using Rufus
1. Insert a clean USB flash drive (8 GB or larger).
2. Download the free [Rufus](https://rufus.ie) utility.
3. Select your USB drive and choose the downloaded Windows 11 `.iso`.
4. Ensure the following settings are selected:
   * Partition scheme: **GPT**
   * Target system: **UEFI (non CSM)**
   * File system: **NTFS**
5. Click **"Start"**.
6. **IMPORTANT:** When Rufus pops up the *"Windows User Experience"* customization dialog (asking to bypass TPM/RAM/online accounts), **UNCHECK ALL BOXES**! Yaro's `autounattend.xml` already handles all bypasses, local account creation, and tweaks. Rufus options can conflict with the automated answer file.

### Step 3. Copy Yaro answer file to USB stick
1. Download **`autounattend.xml`** from this repository.
2. Copy it into the **root directory of your USB flash drive** (alongside `boot`, `efi`, and `sources`).
   *(The path must be `E:\autounattend.xml`, not inside any subfolder).*
3. *(Optional)* Open `autounattend.xml` in Notepad if you wish to adjust your time zone (default: `FLE Standard Time`), local username (default: `User`), or toggle specific tweaks (`Yaro options` block).

### Step 4. (Optional, Recommended) Disable Defender BEFORE setup
If you want Microsoft Defender permanently disabled without any background services or CPU load:
1. Run **`Yaro-Remove-Defender-WIM.cmd`** as Administrator.
2. The script will automatically locate a writable `sources\install.wim` on your USB stick (skipping read-only mounted ISO drives), pick **Windows 11 Pro** (the edition `autounattend.xml` installs), and disable Defender services, kernel drivers, and `TamperProtection` directly in the offline image.
3. See [Complete Windows Defender Removal Guide](#complete-windows-defender-removal-guide) below.

### Step 5. Boot from USB and install
1. Restart your PC and press the **Boot Menu** key during startup  
   *(Commonly **F12**, **F11**, **F8**, **Esc**, or **Fn+F12** depending on your motherboard).*
2. Select your USB drive with the **UEFI** prefix.
3. The automated setup starts immediately. The only prompt requiring user interaction is **disk/partition selection**:
   * Carefully choose your target SSD partition, format it if desired, and click "Next".
4. **Windows handles everything else automatically:**
   * Skips Microsoft account creation, privacy questionnaires, region prompts, and internet checks.
   * Restarts several times and lands directly on your desktop under the local `User` account.

### Step 6. Post-install steps
1. **Install drivers:** install your chipset, network, and GPU drivers (NVIDIA/AMD/Intel) directly from the manufacturer. Yaro blocks Windows Update from auto-installing generic display drivers to prevent driver collisions.
2. **Run `Yaro-Apply.cmd` (Recommended):**
   * Download the repository (*Code → Download ZIP*, or copy the extracted folder from your USB stick) and run **`Yaro-Apply.cmd`** as Administrator.
   * **Why this is important:** Intel software and GPU driver installers often quietly reintroduce background telemetry and tracking services. Running `Yaro-Apply.cmd` creates a clean System Restore Point, strips newly added Intel/OEM telemetry, reinforces the *Ultimate Performance* power plan, and applies user profile tweaks (your existing desktop wallpaper stays untouched unless you set `$SetWallpaper = $true` in `scripts/YaroCommon.ps1`).
3. **Restore Photo Viewer & Snipping Tool (if needed):**
   * When installing with `autounattend.xml` or running `Yaro-Apply.cmd`, classic fast Windows Photo Viewer (13 image formats) is already registered automatically (`$EnablePhotoViewer = $true`).
   * If your Windows image lacked Snipping Tool or you did not apply Yaro and images do not open:
     * **Classic fast Windows Photo Viewer** (PowerShell as Admin):
       ```powershell
       $k = 'HKLM:\SOFTWARE\Microsoft\Windows Photo Viewer\Capabilities\FileAssociations'; foreach ($e in '.jpg','.jpeg','.png','.bmp','.gif','.tiff') { Set-ItemProperty -Path $k -Name $e -Value 'PhotoViewer.FileAssoc.Tiff' }
       ```
     * **Snipping Tool**:
       ```cmd
       winget install 9MZ95KL8MR0L --accept-package-agreements --accept-source-agreements
       ```
4. **Review logs:** check `%SystemRoot%\Setup\Scripts\Yaro\` for full installation transcripts.
5. **Activation:** open *Settings → System → Activation* and activate your Windows 11 Pro edition with your digital license or product key.
6. ***(Optional)* Fast DNS + DoH:** run **`Yaro-DNS.cmd`** to benchmark your router/ISP DNS against major public resolvers, see the fastest server for your connection, and apply IPv4 + IPv6 + encrypted *DoH (On automatic)* **only** if you confirm (`Y`). *(Yaro leaves your DNS unchanged by default; you stay in control.)*

### Step 7. Additional Optimization & App Setup with CTT (Chris Titus Tech WinUtil)

For rapid batch installation of essential software (clean, unattended, no adware) and further fine-tuning, we recommend the open-source **CTT Windows Utility (WinUtil)**:

1. Open **PowerShell as Administrator** (`Win + X` → *Terminal (Admin)* or *PowerShell (Admin)*).
2. Run the command:
   ```powershell
   irm https://christitus.com/win | iex
   ```
3. In the graphical window:
   * **"Install" tab:** select your favorite applications (Chrome/Brave, Telegram, Discord, Steam, 7-Zip, VLC, VS Code, OBS Studio) and click **"Install Selected"**. Winget installs them cleanly in the background.
   * **"Tweaks" tab:** select **Desktop** (for desktop PCs) or **Laptop** (for notebooks) and click **"Run Tweaks"**. Yaro and CTT tweaks complement each other seamlessly.
   * **"Updates" tab:** select **"Security (Recommended)"** to defer feature updates and only receive stable security patches.
   * **Tip:** avoid clicking brute-force options like disabling all services — core Windows services are already expertly configured by Yaro.

---

## Complete Windows Defender Removal Guide

In modern Windows 11, Defender is shielded by kernel-level **Tamper Protection** and Protected Process Light (PPL), preventing standard scripts from stopping services or modifying registry keys on a live system.

Yaro provides two robust solutions:

```
                                 ┌──────────────────────────────────────────────────┐
                                 │      How do you want to disable Defender?        │
                                 └─────────────────────────┬────────────────────────┘
                                                           │
                        ┌──────────────────────────────────┴──────────────────────────────────┐
                        ▼                                                                     ▼
    ┌────────────────────────────────────────┐                            ┌────────────────────────────────────────┐
    │    METHOD 1: BEFORE SETUP (IN WIM)     │                            │     METHOD 2: ON ACTIVE RUNNING OS     │
    ├────────────────────────────────────────┤                            ├────────────────────────────────────────┤
    │ ✔ 100% clean, no workarounds needed    │                            │ ✔ No USB re-flashing required          │
    │ ✔ Services NEVER start even once       │                            │ ✔ Requires toggling 2 UI switches      │
    │ ✔ 0 processes, 0 MB RAM overhead       │                            │ ✔ Run scripts\Remove-Defender-Live.cmd │
    └────────────────────────────────────────┘                            └────────────────────────────────────────┘
```

### Method 1. Offline WIM Disabling Before Installation (100% Clean, Recommended)

While the Windows image is dormant on your USB drive, kernel security hooks (`WdFilter.sys`) are not loaded. Modifying the offline registry hive guarantees 100% success, while Defender's system files remain intact for `sfc` integrity.

1. Flash your USB drive via Rufus (as outlined in Step 2).
2. Right-click **`Yaro-Remove-Defender-WIM.cmd`** → **"Run as Administrator"**.
3. The script automatically locates a writable `sources\install.wim` on your USB stick (skipping read-only mounted ISO drives) or prompts for a path. The edition is chosen automatically: **Windows 11 Pro only** (`EditionId = Professional`, `Build >= 22000`, works on renamed Pro images too; Home, Pro N, Pro Education, and Pro for Workstations are skipped). If the image has no Pro edition, nothing is changed.
4. It performs the following unattended actions:
   * Mounts the WIM image using DISM into a temporary directory;
   * Loads the offline `SYSTEM` and `SOFTWARE` registry hives;
   * Unlocks `NT AUTHORITY\SYSTEM`-protected ACL permissions (`SeTakeOwnershipPrivilege` → `FullControl` for Administrators) on `wscsvc`, `SecurityHealthService`, and `Microsoft Defender\Features` (where `TamperProtection` resides);
   * Sets **`Start = 4` (Disabled)** for `WinDefend`, `WdNisSvc`, `Sense`, `MDCoreSvc`, `webthreatdefsvc`, `webthreatdefusersvc` (`UserServiceFlags = 0`), `wscsvc`, and `SecurityHealthService` (only those present in the image);
   * Disables filesystem filter drivers `WdFilter`, `WdBoot` (ELAM), and `WdNisDrv` *(critical boot driver `MsSecCore` is left untouched)*;
   * Applies anti-spyware policies, sets `TamperProtection = 0`, suppresses UX notifications (`Notification_Suppress = 1`), disables SpyNet telemetry, hides systray, and deletes `SecurityHealth` from Run;
   * Verifies that services (`0x4`) and `TamperProtection` (`0x0`) were actually written, safely unloads the offline hives (up to 5 retries), and commits changes into `install.wim`;
   * Reports the real outcome: **"DONE!"** (`FAILS = 0`) or **"DONE WITH WARNINGS"** listing what failed. If the offline registry cannot be unloaded, nothing is saved and the image stays unchanged.
5. **Outcome:** Upon installing Windows from this USB drive, Defender **never runs at all**: `MsMpEng.exe` is completely absent from Task Manager, background disk scanning is eliminated, and you save 80–150 MB of RAM.

### Method 2. Disabling Defender on an Already Installed Windows

If you have already installed Windows and wish to disable Defender without reinstalling:
1. Run **`scripts\Remove-Defender-Live.cmd`** as Administrator.
2. The script launches the native *Windows Security* settings window.
3. **Manually toggle OFF two switches:**
   * *Real-time protection*;
   * *Tamper Protection*.
4. Return to the command prompt and press any key: the script will immediately apply policies, stop background Defender services, and clean up startup tasks. It then checks which services Windows actually allowed it to disable: if Tamper Protection is still on, you see **"PARTIALLY DONE"** with the list of services.
5. Restart your computer.

---

## Apply to an Existing Windows Installation (Yaro-Apply.cmd)

If you already have a running Windows 11 installation and want to debloat and optimize it:

1. Click **Code → Download ZIP** on GitHub and extract the archive.
2. Run **`Yaro-Apply.cmd`** from the user account you wish to configure (Administrator privileges required).
3. The script creates a System Restore Point, strips pre-installed UWP apps, tunes registry latency parameters, and enables the *Ultimate Performance* power plan.
4. Restart your computer.

---

## Configuration and Options (Yaro options)

To customize behavior, edit the variables in the `Yaro options` block inside `autounattend.xml` (for clean installs) or inside `scripts/YaroCommon.ps1` (for `Yaro-Apply.cmd`). Set to `$true` to apply or `$false` to skip.

| Option | Default | Description |
|---|:---:|---|
| `$DisableDefender` | `$true` | Disables Microsoft Defender (including `MDCoreSvc`, `webthreatdef*`, `wscsvc`, and `Sense.Client`), hides its tray icon, removes `SecurityHealth` from startup and disables Defender's scheduled tasks. |
| `$DisableSmartScreen` | `$true` | Disables SmartScreen checks for downloaded files and untrusted executables. |
| `$SilentUAC` | `$true` | Elevates administrative programs without dimming the screen or prompting confirmation. |
| `$PauseUpdates` | `$true` | Stops automatic update downloads and pauses updates until year 2077 (Ghost Pause), keeping Microsoft Store and `winget` working. |
| `$DisablePrinting` | `$true` | Disables the Print Spooler service and `PrintWorkflowUserSvc` (useful if you do not own a printer). |
| `$DisableBtHandsFree` | `$true` | **Bluetooth Audio Protection:** disables Hands-Free telephony mode. In games with voice chat (CS2, Discord, Grounded), wireless earbuds (AirPods) stay in pristine Hi-Fi Stereo (48 kHz) rather than telephone mono. |
| `$DisableVPN` | `$true` | Disables legacy dial-up and built-in VPN services (RasMan/RasAuto). |
| `$DisableWindowsAI` | `$true` | Removes Copilot / `CoreAI`, disables the `Recall` optional feature, turns off AI features in Notepad, and disables cloud AI tools in Paint (`Cocreator`, `Image Creator`, `Generative Fill`). |
| `$DebloatEdge` | `$true` | Disables Edge sidebar, Copilot/Bing integrations, Shopping Assistant, Rewards, recommendations, startup boost, and telemetry via policies. |
| `$RemoveOneDrive` | `$true` | Uninstalls OneDrive via `OneDriveSetup.exe /uninstall` and disables `OneSyncSvc` (in addition to blocking sync policies). |
| `$EnablePhotoViewer` | `$true` | Registers classic fast Windows Photo Viewer file associations (`.jpg`, `.png`, `.bmp`, `.gif`, `.ico`, etc.). |
| `$DisableBgApps` | `$true` | Prevents Microsoft Store UWP apps from running in the background (`AppPrivacy\LetAppsRunInBackground = 2` system-wide and `GlobalUserDisabled = 1` per-user). |
| `$PreferIPv4` | `$true` | Prefers IPv4 over IPv6 (`DisabledComponents = 32`) without breaking IPv6 for WSL2 or games. |
| `$DisableSearchIndex` | `$true` | Disables the `WSearch` indexing service (set to `$false` if you rely on built-in Windows search rather than tools like Everything). |
| `$DisableHibernation` | `$false` | Fully disables hibernation (`powercfg /h off`) to save SSD space on desktops. *Fast Startup (`HiberbootEnabled = 0`) is always disabled.* |
| `$RemoveIntelApp` | `$false` | Removes `AppUp.IntelGraphicsExperience` (Intel Graphics Command Center) and disables `igccservice`. *The `igfxCUIService` of the old Intel HD Graphics Control Panel (an app Yaro removes) is always set to Manual.* |
| `$ArgonPerformance` | `$true` | High-performance tuning: *Ultimate Performance* power scheme with a 5% minimum CPU state (the CPU cools down at idle and keeps turbo headroom), Game Mode on, `SystemResponsiveness = 10` (the lowest value Windows accepts: it treats 0 as 10), `MMCSS\Tasks\Games` priority (`GPU Priority = 8`, `Priority = 6`, High scheduling & SFIO), `Win32PrioritySeparation = 0x26`, no 8.3 short names. Power throttling of background apps stays with Windows: it never slows the active game, leaves it more thermal headroom and moves background work to E-cores on 12th–14th gen Intel. Laptop battery drains faster. |
| `$ForceMSI` | `$false` | Forces MSI (Message Signaled Interrupts) mode for GPU, NVMe, and network adapters to minimize DPC latency. |
| `$SetWallpaper` | `$true` *(USB setup)* / `$false` *(`Yaro-Apply`)* | Sets the signature minimalist Yaro wallpaper. Enabled during clean USB installation (`autounattend.xml`), disabled by default in `Yaro-Apply.cmd` (`scripts/YaroCommon.ps1`) so your existing wallpaper is preserved. |

---

## Detailed Optimizations Breakdown

### Removed Bloatware, AI & Telemetry
* Strips all non-essential UWP packages: Clipchamp, Microsoft News, Weather, Feedback Hub, DevHome, Bing Search, Copilot / `CoreAI`, Edge GameAssist, Cortana, Solitaire, Office Hub, People, new Outlook, and consumer promo content.
* Prevents `UScheduler_Oobe` from silently reinstalling Outlook and Dev Home when connected to the internet, clears Start pins on clean installs, and suppresses Microsoft Account promotional prompts.
* Turns off the advertising ID for all users by policy (`AdvertisingInfo\DisabledByGroupPolicy`) and stops handing the Windows language list to websites and apps (`HttpAcceptLanguageOptOut`).
* Disables user telemetry (`AdvertisingInfo`, `TIPC`, `TailoredExperiences`, `Start_TrackProgs`, `Siuf`), `whesvc`, `lfsvc` geolocation service, WER upload tasks (`QueueReporting`, keeping local dumps functional), and `Flighting` / `CEIP` / `Diagnosis` telemetry tasks.
* Less background work: disables background Store auto-updates (`AutoDownload = 2`, Store & `winget` still work manually), disables LLMNR multicast (`EnableMulticast = 0`), sets `AppCaptureEnabled = 0` (prevents `ms-gamingoverlay` popups), disables the `Autochk\Proxy`, `Device Information` (device census), `SustainabilityTelemetry`, `PerformanceTrace` (feedback toasts), `AccountHealth` (account reminders) and `Power Efficiency Diagnostics` (periodic power analysis) tasks. Turns off Start recommendations and account notifications, sync-provider ads in Explorer, "Suggested" toasts, Settings notifications, typing insights, lock screen fun facts, cloud search and Click to Do.

### System Responsiveness, Latency & Explorer UX
* **SvcHost Grouping:** sets `SvcHostSplitThresholdInKB = 0xffffffff`, consolidating fragmented svchost processes down to ~55–60 (with `PushToInstall` disabled so triggers cannot stall `netsvcs`).
* **`C:\Windows\Temp` permissions:** when a cleaner deletes and recreates the folder, its permissions break and installers fail at ~90% with errors **2503 / 2502**. Yaro checks them and restores the Windows defaults when needed.
* **WinTrust Fix:** eliminates the notorious 2-minute freeze during driver/app installations by preventing CRL network timeouts (`State = 0x23C00` + `ChainEngine` 200/500ms).
* **Explorer & UX:** `MenuShowDelay = 0` ms, instant startup app launch without the 10-second logon pause (`StartupDelayInMSec = 0`), `TaskbarEndTask`, classic Windows 10 context menu, Explorer opens to "This PC" (`LaunchTo = 1`), hides Home & Gallery, shows file extensions (`HideFileExt = 0`), disables Sticky Keys prompt (`506`), disables mouse acceleration (`MouseSpeed = 0`), disables `SysMain` (`Superfetch`), disables Fast Startup (`HiberbootEnabled = 0`), and enables verbose BSoD crash info.

---

## Wallpapers

Yaro includes custom 1920×1080 notebook-paper wallpapers crafted for light and dark desktop themes:

**Light Themes**

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

**Dark Themes**

<table>
<tr>
<td align="center"><a href="assets/yaro-wallpaper-dark-night.png"><img src="assets/yaro-wallpaper-dark-night.png" width="280" alt="night sky"></a><br><sub>night sky</sub></td>
<td align="center"><a href="assets/yaro-wallpaper-dark-plum.png"><img src="assets/yaro-wallpaper-dark-plum.png" width="280" alt="plum"></a><br><sub>plum</sub></td>
<td align="center"><a href="assets/yaro-wallpaper-dark-ocean.png"><img src="assets/yaro-wallpaper-dark-ocean.png" width="280" alt="ocean"></a><br><sub>ocean</sub></td>
</tr>
<tr>
<td align="center"><a href="assets/yaro-wallpaper-dark-forest.png"><img src="assets/yaro-wallpaper-dark-forest.png" width="280" alt="forest"></a><br><sub>forest</sub></td>
<td align="center"><a href="assets/yaro-wallpaper-dark-cocoa.png"><img src="assets/yaro-wallpaper-dark-cocoa.png" width="280" alt="cocoa"></a><br><sub>cocoa</sub></td>
<td align="center"><a href="assets/yaro-wallpaper-dark-paper-real.png"><img src="assets/yaro-wallpaper-dark-paper-real.png" width="280" alt="black paper"></a><br><sub>black paper</sub></td>
</tr>
<tr>
<td align="center"><a href="assets/yaro-wallpaper-dark-navy.png"><img src="assets/yaro-wallpaper-dark-navy.png" width="280" alt="navy"></a><br><sub>navy</sub></td>
<td align="center"><a href="assets/yaro-wallpaper-dark-graphite.png"><img src="assets/yaro-wallpaper-dark-graphite.png" width="280" alt="graphite"></a><br><sub>graphite</sub></td>
<td align="center"><a href="assets/yaro-wallpaper-dark-grid.png"><img src="assets/yaro-wallpaper-dark-grid.png" width="280" alt="black grid"></a><br><sub>black grid</sub></td>
</tr>
</table>

---

## License & Disclaimer

* Licensed under the [MIT License](LICENSE).
* Not affiliated with or endorsed by Microsoft Corporation. Windows is a registered trademark of Microsoft Corporation.
