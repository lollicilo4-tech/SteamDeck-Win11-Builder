<#
    First-boot setup for Windows 11 on the Steam Deck OLED.
    Starts by itself at the first sign-in; you can run it again any time
    with "Steam Deck Setup" on the desktop: steps already done are skipped.
#>

# --- Run as administrator ---------------------------------------------------
$principal = New-Object Security.Principal.WindowsPrincipal ([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$Root     = 'C:\DeckSetup'
$StateDir = Join-Path $Root 'state'
$Drivers  = 'C:\DeckDrivers'
New-Item -ItemType Directory -Path $StateDir -Force | Out-Null
Start-Transcript -Path (Join-Path $Root 'postinstall.log') -Append | Out-Null
$Host.UI.RawUI.WindowTitle = 'Steam Deck Setup'

function Write-Step([string]$Message) { Write-Host ''; Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Info([string]$Message) { Write-Host "    $Message" }
function Write-Warn([string]$Message) { Write-Host "    WARNING: $Message" -ForegroundColor Yellow }
function Test-Done([string]$Name) { Test-Path -LiteralPath (Join-Path $StateDir "$Name.ok") }
function Set-Done([string]$Name)  { New-Item -ItemType File -Path (Join-Path $StateDir "$Name.ok") -Force | Out-Null }

function Read-YesNo([string]$Question, [bool]$Default = $true) {
    $hint = if ($Default) { '[Y/n]' } else { '[y/N]' }
    $a = Read-Host "    $Question $hint"
    if ([string]::IsNullOrWhiteSpace($a)) { return $Default }
    return ($a.Trim() -match '^[yYsS]')
}

Clear-Host
Write-Host '=============================================' -ForegroundColor Cyan
Write-Host '  Windows 11 for Steam Deck OLED - setup'     -ForegroundColor Cyan
Write-Host '=============================================' -ForegroundColor Cyan
Write-Host 'Use the touchscreen or a keyboard to answer.'
Write-Host "If an installer asks to restart, choose 'later'."

# ---------------------------------------------------------------------------
# 1. Valve drivers
# ---------------------------------------------------------------------------
if (-not (Test-Done 'drivers') -and (Test-Path -LiteralPath $Drivers)) {
    Write-Step "Installing Valve's drivers"
    # APU (graphics) first, then the rest
    $packages = Get-ChildItem -LiteralPath $Drivers | Sort-Object @{ Expression = { if ($_.Name -match 'APU|GPU|Graphics') { 0 } else { 1 } } }, Name
    foreach ($pkg in $packages) {
        $runner = $null
        if ($pkg.PSIsContainer) {
            # (-Include is ignored together with -LiteralPath in PowerShell 5.1: filter by hand)
            $runner = Get-ChildItem -LiteralPath $pkg.FullName -Recurse -Depth 2 -File |
                Where-Object { $_.Name -in 'install.bat', 'setup.exe' } |
                Sort-Object @{ Expression = { $_.FullName.Length } } | Select-Object -First 1
        } elseif ($pkg.Extension -in '.exe', '.msi') {
            $runner = $pkg
        }
        if (-not $runner) { continue }
        Write-Info "$($pkg.Name): running $($runner.Name)"
        switch ($runner.Extension.ToLower()) {
            '.bat' { Start-Process cmd.exe -ArgumentList "/c `"$($runner.FullName)`"" -WorkingDirectory $runner.DirectoryName -Wait }
            '.msi' { Start-Process msiexec.exe -ArgumentList "/i `"$($runner.FullName)`" /passive /norestart" -Wait }
            default { Start-Process -FilePath $runner.FullName -WorkingDirectory $runner.DirectoryName -Wait }
        }
    }
    Write-Info 'final pass on the .inf drivers'
    $null = & pnputil.exe /add-driver "$Drivers\*.inf" /subdirs /install 2>&1
    Set-Done 'drivers'
}

# ---------------------------------------------------------------------------
# 2. Landscape screen (the Deck panel is natively portrait)
# ---------------------------------------------------------------------------
if (-not (Test-Done 'display')) {
    Write-Step 'Screen orientation'
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class DeckDisplay {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DEVMODE {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
        public short dmSpecVersion; public short dmDriverVersion; public short dmSize; public short dmDriverExtra;
        public int dmFields; public int dmPositionX; public int dmPositionY;
        public int dmDisplayOrientation; public int dmDisplayFixedOutput;
        public short dmColor; public short dmDuplex; public short dmYResolution; public short dmTTOption; public short dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
        public short dmLogPixels; public int dmBitsPerPel; public int dmPelsWidth; public int dmPelsHeight;
        public int dmDisplayFlags; public int dmDisplayFrequency; public int dmICMMethod; public int dmICMIntent;
        public int dmMediaType; public int dmDitherType; public int dmReserved1; public int dmReserved2;
        public int dmPanningWidth; public int dmPanningHeight;
    }
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern bool EnumDisplaySettings(string deviceName, int modeNum, ref DEVMODE devMode);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern int ChangeDisplaySettings(ref DEVMODE devMode, int flags);

    static DEVMODE Current() {
        DEVMODE dm = new DEVMODE();
        dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
        EnumDisplaySettings(null, -1, ref dm);
        return dm;
    }
    public static bool IsPortrait() { DEVMODE dm = Current(); return dm.dmPelsHeight > dm.dmPelsWidth; }
    public static int SetOrientation(int orientation) {
        DEVMODE dm = Current();
        if ((dm.dmDisplayOrientation % 2) != (orientation % 2)) {
            int t = dm.dmPelsWidth; dm.dmPelsWidth = dm.dmPelsHeight; dm.dmPelsHeight = t;
        }
        dm.dmDisplayOrientation = orientation;
        dm.dmFields = 0x80 | 0x80000 | 0x100000;   // orientation, width, height
        return ChangeDisplaySettings(ref dm, 1);   // 1 = save to registry
    }
}
'@
    if ([DeckDisplay]::IsPortrait()) {
        $r = [DeckDisplay]::SetOrientation(1)
        if ($r -ne 0) {
            Write-Warn "rotation failed (code $r): rotate it from Settings > System > Display > Display orientation"
        } elseif (-not (Read-YesNo 'Is the screen now landscape and the right way up?')) {
            $null = [DeckDisplay]::SetOrientation(3)
            if (-not (Read-YesNo 'And now?')) {
                Write-Warn 'fix it from Settings > System > Display > Display orientation'
            }
        }
    } else {
        Write-Info 'already landscape'
    }
    Set-Done 'display'
}

# ---------------------------------------------------------------------------
# 3. Internet connection
# ---------------------------------------------------------------------------
function Test-Internet {
    try {
        $r = Invoke-WebRequest -Uri 'http://www.msftconnecttest.com/connecttest.txt' -UseBasicParsing -TimeoutSec 5
        return ($r.Content -like 'Microsoft Connect Test*')
    } catch { return $false }
}

$online = Test-Internet
if (-not $online) {
    Write-Step 'Internet connection'
    Start-Process 'ms-availablenetworks:' -ErrorAction SilentlyContinue
    while (-not $online) {
        Write-Info 'Connect to Wi-Fi from the panel that just opened (or the network icon at the bottom right).'
        $a = Read-Host '    Press ENTER when connected, or type S to skip'
        if ($a -match '^[sS]') { break }
        $online = Test-Internet
        if (-not $online) { Write-Warn 'still no connection' }
    }
}

# ---------------------------------------------------------------------------
# 4. Steam and Handheld Companion
# ---------------------------------------------------------------------------
function Get-Winget {
    $w = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $w) {
        try { Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Stop } catch { }
    }
    for ($i = 0; -not $w -and $i -lt 18; $i++) {
        Start-Sleep -Seconds 10
        $w = Get-Command winget.exe -ErrorAction SilentlyContinue
    }
    return $w
}

if ($online -and -not (Test-Done 'apps')) {
    Write-Step 'Installing Steam and Handheld Companion'
    Write-Info 'waiting for winget to be ready (it can take a minute on first boot)...'
    $winget = Get-Winget
    if (-not $winget) {
        Write-Warn 'winget not available: update "App Installer" from the Microsoft Store and run this script again.'
    } else {
        $apps = @(
            @{ Id = 'Valve.Steam';                   Name = 'Steam' },
            @{ Id = 'BenjaminLSR.HandheldCompanion'; Name = 'Handheld Companion (controls, TDP, overlay)' }
        )
        $allOk = $true
        foreach ($app in $apps) {
            Write-Info "installing $($app.Name)..."
            & $winget.Source install --id $app.Id --exact --source winget --silent `
                --accept-package-agreements --accept-source-agreements --disable-interactivity
            # 0 = installed, -1978335189 = already installed and up to date
            if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) {
                Write-Warn "$($app.Name) not installed (code $LASTEXITCODE)"
                $allOk = $false
            }
        }
        if ($allOk) { Set-Done 'apps' }
    }
}

# ---------------------------------------------------------------------------
# 5. Lossless Scaling (frame generation): the Windows original of the Decky LSFG-VK plugin
# ---------------------------------------------------------------------------
$steam = Join-Path ${env:ProgramFiles(x86)} 'Steam\steam.exe'
if ((Test-Path -LiteralPath $steam) -and -not (Test-Done 'lossless')) {
    Write-Step 'Frame generation (Lossless Scaling)'
    Write-Info 'It is the paid Steam app the Decky LSFG-VK plugin is based on: on Windows you run the original.'
    if (Read-YesNo 'Do you own it (or want to buy it) and install it now?' $false) {
        Start-Process 'steam://install/993090'
        Write-Info 'Steam opens: sign in if needed and confirm the install. See the README for settings.'
    }
    Set-Done 'lossless'
}

# ---------------------------------------------------------------------------
# 6. Steam Big Picture at startup
# ---------------------------------------------------------------------------
if ((Test-Path -LiteralPath $steam) -and -not (Test-Done 'bigpicture')) {
    Write-Step 'Startup'
    if (Read-YesNo 'Start Steam in Big Picture mode at every boot (console-like experience)?') {
        New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'Steam' `
            -Value "`"$steam`" -gamepadui" -PropertyType String -Force | Out-Null
        Write-Info 'done'
    }
    Set-Done 'bigpicture'
}

# ---------------------------------------------------------------------------
# End
# ---------------------------------------------------------------------------
Write-Host ''
$pending = @('drivers', 'display', 'apps') | Where-Object { -not (Test-Done $_) }
if ($pending.Count -eq 0) {
    Write-Host 'Setup complete.' -ForegroundColor Green
    Remove-Item -LiteralPath 'C:\Users\Public\Desktop\Steam Deck Setup.cmd' -Force -ErrorAction SilentlyContinue
} else {
    Write-Host ("Still to do: {0}. Run 'Steam Deck Setup' from the desktop again." -f ($pending -join ', ')) -ForegroundColor Yellow
}
Write-Host "Log: $Root\postinstall.log"
Stop-Transcript | Out-Null

if (Read-YesNo 'Restart now? (recommended after installing drivers)') { Restart-Computer -Force }
