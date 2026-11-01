# SteamDeck-Win11-Builder

Scripts that turn the **official** Windows 11 ISO into a debloated build ready for the **Steam Deck OLED**: Valve's drivers baked in, useless apps removed, a near-unattended install and a first-boot setup that installs Steam and Handheld Companion.

> **No modified ISO is distributed here.** You build your own from Microsoft's ISO and Valve's drivers, both downloaded from their official sites. Read the scripts before running them: they are plain PowerShell.

🇮🇹 [Leggimi in italiano](README.it.md)

## Why

Some games with kernel anti-cheat don't run on SteamOS (for example EA SPORTS FC and Fortnite). Windows runs them, but a stock install on the Deck is heavy and full of things a handheld doesn't need. This kit gives you a lean Windows that feels closer to a console.

## What you need

- A PC with Windows 10 or 11 and about **35 GB free** on C: (7 GB for the ISO plus the work space)
- A USB stick of **16 GB or more** (USB-C, or with an adapter or hub)
- Valve's Windows drivers for the Steam Deck **OLED**: the kit opens the right page, you download them into a folder (zip files are fine)
- [Rufus](https://rufus.ie)
- Recommended: a USB-C hub with keyboard and mouse. Touch works, but Windows Setup shows up in portrait

## Before wiping SteamOS

1. Update SteamOS to the latest stable version: this also installs the latest BIOS, which Bluetooth needs under Windows.
2. Back up saves that aren't in Steam Cloud (emulators, non-Steam games).
3. To go back to SteamOS later, use Valve's official recovery image.

## 1. Build the ISO (on the PC)

1. Download this repository (green **Code** button → **Download ZIP**) and extract it.
2. Double-click **Build-ISO.cmd** and accept the administrator prompt.
3. Answer **Y** when asked to download the ISO: it gets the latest Windows 11 from Microsoft's servers, in the same language as your PC (via [Fido](https://github.com/pbatard/Fido), the tool Rufus uses). If the automatic download is blocked, it opens Microsoft's page so you can download it manually. If you already have the ISO, answer **n** and pick it.
4. Valve's driver page opens: download the Steam Deck OLED drivers, press ENTER and pick the folder you saved them in.
5. Wait 30-60 minutes plus the download. You'll find `Win11-SteamDeckOLED.iso` (and a log) in the kit folder. The original ISO stays in `Download`, so a second run doesn't download it again.

The progress bar can sit on the same percentage for 15-20 minutes during cleanup and compression: that's normal, don't close the window.

### Options

Run `Build-DeckWin11.ps1` from Windows PowerShell as administrator:

| Option | Effect |
|---|---|
| `-IsoLanguage "English International"` | Language of the downloaded ISO (default: same as your PC) |
| `-UserName Max` | Local account name (default `Deck`) |
| `-Password "..."` | Account password (default none) |
| `-Edition Home` | Edition to keep (default `Pro`) |
| `-Locale`, `-KeyboardLayout`, `-TimeZone` | Regional settings (default: same as your PC) |
| `-RemoveXbox` | Also remove the Xbox app and Game Bar |
| `-AllowWindowsUpdateDrivers` | Let Windows Update replace drivers |
| `-SkipComponentCleanup` | Faster, slightly bigger ISO |
| `-KeepVBS` | Keep Memory Integrity on (see below) |
| `-CompactOS` | Compress Windows files: about 2-3 GB less on disk |
| `-KeepWorkDir` | Keep `C:\DeckBuild` at the end |

Example: `.\Build-DeckWin11.ps1 -IsoLanguage German -UserName Max -RemoveXbox`

## 2. Prepare the USB stick

In Rufus pick the ISO you built, partition scheme **GPT**, target **UEFI**. When Rufus shows the "Windows User Experience" dialog (local account, requirements, etc.) **untick everything**: the kit already does it, and Rufus' settings could conflict with it.

## 3. Install on the Deck

1. Deck off, USB stick plugged in: hold **Volume Down** and press **Power**, then pick the USB stick in the Boot Manager.
2. Setup appears in portrait: that's normal.
3. At the disk step delete **all** partitions of the internal drive (the 512 GB or 1 TB one, usually "Drive 0"). Don't touch the USB stick or the microSD card. Select the unallocated space and click Next. This can't be undone.
4. If asked for a product key choose **"I don't have a product key"**. Windows activates with your digital license, if you have one.
5. When the screen goes black for the first restart, unplug the USB stick.
6. The rest is automatic: no Microsoft account, no privacy questions.

## 4. First boot

**Steam Deck Setup** opens by itself and:

- runs Valve's driver installers (if one asks to restart, choose "later")
- rotates the screen to landscape and asks you if it's the right way up
- helps you connect to Wi-Fi
- installs **Steam** and **Handheld Companion** (controls as an Xbox pad, TDP, overlay)
- offers to install **Lossless Scaling** for frame generation (see below)
- offers to start Steam in **Big Picture** at every boot

You can run it again from the desktop icon: steps already done are skipped. Logs are in `C:\DeckSetup`.

## What changes compared to stock Windows

**Apps removed:** Copilot, Teams, new Outlook, Mail, Clipchamp, News, Weather, Solitaire, To Do, Sticky Notes, Feedback Hub, Maps, Phone Link, Family, Quick Assist, Dev Home, Power Automate, Camera, Widgets, OneDrive.

**Components removed:** Recall, IE mode, Windows Hello face, legacy Windows Media Player, legacy Paint, WordPad, PowerShell ISE, Steps Recorder, Fax and Scan, handwriting and math recognition, extra wallpapers, PowerShell 2.0, Work Folders, XPS services.

**Kept:** Microsoft Store, winget, Edge (many launchers need it), Photos, Paint, Notepad, Calculator, Snipping Tool, Terminal, Media Player, Xbox app and Game Bar, regular printing.

**Performance and battery:** Memory Integrity and VBS off, telemetry and useless services disabled, Edge doesn't stay loaded in the background, updates without uploads to other PCs, no background game recording, hibernation off, no reserved storage, no automatic disk encryption.

**Console-like:** no lock screen, edge swipes don't open panels while gaming, no forced update reboots while you're signed in, no Sticky Keys popup, compact taskbar, touch keyboard pops up automatically.

**Privacy:** minimal telemetry, no sponsored apps, suggestions or ads in Start, Copilot off, Windows Update on but without replacing Valve's drivers.

### Memory Integrity (VBS)

It's on by default in Windows 11 and costs a few percent of FPS on an APU like the Deck's. The kit turns it off: you gain performance but lose a layer of protection against malicious drivers. If you also use the Deck for work or prefer security, build with `-KeepVBS`.

## Frame generation with Lossless Scaling (instead of Decky)

The Decky plugin **LSFG-VK** is a Linux port of the Windows app **Lossless Scaling**, and even on SteamOS it requires owning it on Steam. On Windows you just use the original, always up to date and compatible with DirectX, Vulkan and OpenGL.

Decky Loader on Windows exists, but the project calls it unsupported and unstable, and most plugins are written for SteamOS. The **Handheld Companion** quick menu already covers TDP, profiles and controls.

**Recommended setup on the Deck OLED (90 Hz screen):**

1. Install Lossless Scaling from Steam (the first-boot script offers it).
2. Set the game to **borderless window**: exclusive fullscreen isn't supported.
3. Cap the game at **45 FPS** (half of 90), from the game settings or RivaTuner (RTSS). A stable base matters more than a high one.
4. In Lossless Scaling: frame generation **LSFG**, multiplier **X2** (45 → 90 FPS), or **adaptive** mode with a target of 90.
5. If the game loses smoothness, lower **Flow scale** or enable **Performance mode**: frame generation uses the same GPU as the game, so it needs headroom.
6. If the image isn't captured, try the other capture API (WGC or DXGI).
7. Save a **per-game profile** in Lossless Scaling.

**One-button toggle:** the Lossless Scaling shortcut is **Ctrl+Alt+S**. Map it to a back button (L4/R4): for Steam games from the Steam Input layout (extra command on the button), for others from Handheld Companion.

**Limits:** frame generation adds smoothness, not responsiveness. It adds a bit of input lag and looks bad if the base drops below 40 FPS. Leave it off for competitive games.

## Tips for smoother games

- **90 Hz and an even frame cap:** set the screen to 90 Hz (Settings → Display → Advanced display) and cap games at 30, 45 or 90 FPS. An uneven cap like 60 on 90 Hz stutters even at high FPS. "V-Sync 50%" in a game means 45 FPS at 90 Hz.
- **Per-game TDP profiles** in Handheld Companion (up to 15 W on the OLED), and Windows power mode on **Best performance** for heavy games.
- **Startup apps:** disable the EA app, Epic Games Launcher, Discord and similar in Task Manager → Startup apps.
- **More video memory:** if a DirectX 12 game stutters, raise the GPU memory in the BIOS: Deck off → hold **Volume Up** and press **Power** → Setup Utility → Advanced → **UMA Frame Buffer Size** → **4G** → Exit Saving Changes. 12 GB stay for the system; set it back to 1G if a game gets worse.

## Troubleshooting

- **"Unknown devices" in Device Manager** (VLV0100, PRP0001, ANX7580A/D, AMDI8821, PCI encryption/decryption controller): components with no official Windows driver. They're normal and don't affect games, audio, Wi-Fi or controls.
- **DirectX error `DXGI_ERROR_INVALID_CALL` when starting a game** (for example EA SPORTS FC): the game is trying exclusive fullscreen. Set it to **borderless window**. For EA SPORTS FC, edit `fcsetup.ini` in `%LOCALAPPDATA%\EA SPORTS FC <year>` and set `FULLSCREEN = 0`, `WINDOWED_BORDERLESS = 1`, `RESOLUTIONHEIGHT = 800`. If it still fails, also set `WAITFORVSYNC = 0`.
- **Games that need Secure Boot** (Battlefield 6, Call of Duty Black Ops 7, Valorant, Fortnite tournaments) won't run: the Deck doesn't offer Secure Boot for Windows. Regular Fortnite matches and EA SPORTS FC work.
- **Red errors while the first-boot script installs drivers**, saying no application is associated with a `.sys` file: fixed in this version. If you see them, they're harmless: drivers are also installed from their `.inf` files.
- **The build stopped at "Creating the ISO"**: don't run Build-ISO.cmd again (it starts over from scratch and deletes `C:\DeckBuild`). Everything is ready in `C:\DeckBuild\iso`; finish it from Windows PowerShell as administrator:

  ```powershell
  $iso = 'C:\DeckBuild\iso'; $exe = 'C:\DeckBuild\oscdimg.exe'
  $efi = "$iso\efi\microsoft\boot\efisys_noprompt.bin"; if (-not (Test-Path $efi)) { $efi = "$iso\efi\microsoft\boot\efisys.bin" }
  & $exe -m -o -u2 -udfver102 -lDECK_WIN11 "-bootdata:2#p0,e,b$iso\boot\etfsboot.com#pEF,e,b$efi" $iso "$env:USERPROFILE\Desktop\Win11-SteamDeckOLED.iso"
  ```

- **Anything else:** the log next to the ISO (`Win11-SteamDeckOLED.log`) and `C:\DeckSetup\postinstall.log` on the Deck say where it stopped. Open an issue and attach them.

## Good to know

- Valve provides **no support** for Windows on the Deck. Use this kit at your own risk.
- When Valve publishes new drivers, download and install them manually (Windows Update doesn't, on purpose).
- For non-Steam games, use Handheld Companion to expose the controls as an Xbox pad.
- Tested on a Steam Deck OLED with Windows 11 25H2 and Valve's August 2024 drivers. Other ISO and driver combinations may behave differently.
- The LCD Steam Deck isn't tested: its drivers are different.

## Credits

- [Tiny11 Builder](https://github.com/ntdevlabs/tiny11builder) by NTDEV, for many of the registry tweaks
- [Fido](https://github.com/pbatard/Fido) by Pete Batard, for the official ISO download
- [Handheld Companion](https://github.com/Valkirie/HandheldCompanion) for controls and TDP on Windows

## License

[MIT](LICENSE). Windows is a trademark of Microsoft; Steam and Steam Deck are trademarks of Valve. This project is not affiliated with either.
