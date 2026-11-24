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
> [What Yaro turns off](#what-yaro-turns-off) and [Options](#configuration-and-options) before installing.
> Try it in a virtual machine first. Use at your own risk.

---

## Repository Files

| File | Description |
|---|---|
| `autounattend.xml` | Primary answer file for fully unattended clean install from a USB stick. |
| `Yaro-Remove-Defender-WIM.cmd` | **Automated offline Defender removal script** directly in `install.wim` BEFORE setup. |
| `Yaro-Apply.cmd` | Applies Yaro debloat and optimizations to an existing, already installed Windows 11. |
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

### Step 4. (Optional, Recommended) Remove Defender BEFORE setup
If you want Microsoft Defender permanently disabled without any background services or CPU load:
1. Run **`Yaro-Remove-Defender-WIM.cmd`** as Administrator.
2. The script will automatically locate `sources\install.wim` on your USB stick and disable Defender services and kernel drivers directly in the offline image.
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
   * **Why this is important:** Intel software and GPU driver installers often quietly reintroduce background telemetry and tracking services. Running `Yaro-Apply.cmd` creates a clean System Restore Point, strips newly added Intel/OEM telemetry, reinforces the *Ultimate Performance* power plan, applies user profile tweaks, and sets the signature Yaro wallpaper.
3. **Restore Photo Viewer & Snipping Tool (if needed):**
   * If your Windows edition lacked these apps or you installed offline without initial Store provisioning:
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

### Method 1. Offline WIM Removal Before Installation (100% Clean, Recommended)

While the Windows image is dormant on your USB drive, kernel security hooks (`WdFilter.sys`) are not loaded. Modifying the offline registry hive guarantees 100% success without access denials.

1. Flash your USB drive via Rufus (as outlined in Step 2).
2. Right-click **`Yaro-Remove-Defender-WIM.cmd`** → **"Run as Administrator"**.
3. The script automatically detects `sources\install.wim` on your USB stick.
4. It performs the following unattended actions:
   * Mounts the WIM image using DISM into a temporary directory;
   * Loads the offline `SYSTEM` and `SOFTWARE` registry hives;
   * Sets **`Start = 4` (Disabled)** for `WinDefend`, `WdNisSvc`, `Sense`, and `SecurityHealthService`;
   * Disables filesystem filter drivers `WdFilter`, `WdBoot` (ELAM), and `WdNisDrv`;
   * Applies anti-spyware policies, disables SpyNet telemetry, and removes systray hooks;
   * Saves the changes directly into `install.wim` and cleanly unmounts.
5. **Outcome:** Upon installing Windows from this USB drive, Defender **never runs at all**: `MsMpEng.exe` is completely absent from Task Manager, background disk scanning is eliminated, and you save 80–150 MB of RAM.

### Method 2. Disabling Defender on an Already Installed Windows

If you have already installed Windows and wish to disable Defender without reinstalling:
1. Run **`scripts\Remove-Defender-Live.cmd`** as Administrator.
2. The script launches the native *Windows Security* settings window.
3. **Manually toggle OFF two switches:**
   * *Real-time protection*;
   * *Tamper Protection*.
4. Return to the command prompt and press any key: the script will immediately apply policies, stop background Defender services, and clean up startup tasks.
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

To customize behavior, edit the variables at the top of `autounattend.xml` (for clean installs) or inside `scripts/YaroCommon.ps1` (for `Yaro-Apply.cmd`). Set to `$true` to apply or `$false` to skip.

| Option | Default | Description |
|---|:---:|---|
| `$DisableDefender` | `$true` | Disables Microsoft Defender and removes its taskbar tray icon. |
| `$DisableSmartScreen` | `$true` | Disables SmartScreen checks for downloaded files and untrusted executables. |
| `$SilentUAC` | `$true` | Elevates administrative programs without dimming the screen or prompting confirmation. |
| `$PauseUpdates` | `$true` | Stops automatic update downloads and pauses updates until year 2077 (Ghost Pause). |
| `$DisablePrinting` | `$true` | Disables the Print Spooler service (useful if you do not own a printer). |
| `$DisableBtHandsFree` | `$true` | **Bluetooth Audio Protection:** disables Hands-Free telephony mode. In games with voice chat (CS2, Discord, Grounded), wireless earbuds (AirPods) stay in pristine Hi-Fi Stereo (48 kHz) rather than telephone mono. |
| `$DisableVPN` | `$true` | Disables legacy dial-up and built-in VPN services (RasMan/RasAuto). |
| `$ArgonPerformance` | `$true` | High-performance tuning: *Ultimate Performance* power scheme, 5% minimum CPU state (prevents idle overheating), SvcHost grouping (reduces process count from 90+ down to ~55), and 0ms menu delay. |
| `$ForceMSI` | `$false` | Forces MSI (Message Signaled Interrupts) mode for GPU, NVMe, and network adapters to minimize DPC latency. |
| `$SetWallpaper` | `$true` | Sets the signature minimalist Yaro wallpaper. |

---

## Detailed Optimizations Breakdown

### Removed Bloatware & Telemetry
* Strips all non-essential UWP packages: Clipchamp, Microsoft News, Weather, Feedback Hub, DevHome, Edge GameAssist, Cortana, Solitaire, Xbox TCUI, Office Hub, People, and consumer promo content.
* Disables telemetry collection, WER crash reporting, CEIP diagnostics, and telemetry scheduled tasks.

### System Responsiveness & Low Latency
* **SvcHost Grouping:** sets `SvcHostSplitThresholdInKB = 0xffffffff`, consolidating fragmented svchost processes down to ~55–60.
* **WinTrust Fix:** eliminates the notorious 2-minute freeze during driver/app installations by preventing CRL network timeouts (`State = 0x23C00`).
* **Instant UI:** `MenuShowDelay` is reduced to 0ms for instant context menus, and `TaskbarEndTask` is enabled directly in the taskbar right-click menu.

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
