#Requires -RunAsAdministrator
#Requires -Version 5.1
<#
.SYNOPSIS
    Builds a debloated Windows 11 ISO preconfigured for the Steam Deck OLED.

.DESCRIPTION
    Starts from the official Microsoft ISO and:
      - keeps a single edition (Pro by default)
      - removes preinstalled apps that are useless on a handheld (Copilot, Teams, Outlook, Clipchamp, news...)
      - keeps the Store, App Installer (winget) and the Xbox app / Game Bar (remove them with -RemoveXbox)
      - removes optional components (Recall, IE mode, Windows Hello face, WordPad, Fax...)
      - injects Valve's Steam Deck OLED drivers and copies them to C:\DeckDrivers
      - applies registry tweaks (telemetry, sponsored apps, automatic BitLocker, reserved storage,
        VBS, lock screen, edge swipes, touch keyboard, compact taskbar)
      - adds an unattended setup (local account, no Microsoft account, no privacy screens)
      - adds a first-boot script that installs Steam and Handheld Companion

    Run it on a Windows 10/11 PC, in Windows PowerShell 5.1 started as administrator.
    Needs about 35 GB of free space and 30-60 minutes plus the ISO download.

.EXAMPLE
    Double-click Build-ISO.cmd: it downloads the ISO and asks for the drivers folder.

.EXAMPLE
    .\Build-DeckWin11.ps1 -IsoPath "D:\Win11_25H2_English_x64.iso" -DriversPath "D:\DeckOLEDDrivers"

.EXAMPLE
    .\Build-DeckWin11.ps1 -IsoLanguage German -UserName Max -Password "secret" -RemoveXbox
#>
[CmdletBinding()]
param(
    # Official Windows 11 ISO. If missing, the script downloads it from Microsoft (or lets you pick it)
    [string] $IsoPath = '',
    # Language of the ISO to download, as Microsoft names it (English, English International, Italian,
    # German...). Empty = same language as this PC
    [string] $IsoLanguage = '',
    # Folder with Valve's Steam Deck OLED drivers, zip files are fine (if missing, the script asks)
    [string] $DriversPath = '',
    # ISO to create (next to the script by default)
    [string] $OutputIso = '',
    # Temporary work folder (no spaces in the path)
    [string] $WorkDir = 'C:\DeckBuild',
    # Edition to keep: Pro, Home, Education...
    [string] $Edition = 'Pro',
    # Local account created automatically
    [string] $UserName = 'Deck',
    # Leave empty to sign in without a password
    [string] $Password = '',
    [string] $ComputerName = 'STEAMDECK',
    # Regional format, keyboard and time zone. Empty = same as this PC
    [string] $Locale = '',
    [string] $KeyboardLayout = '',
    [string] $TimeZone = '',
    # Also remove the Xbox app and Game Bar
    [switch] $RemoveXbox,
    # By default Windows Update does NOT replace Valve's drivers: this switch allows it
    [switch] $AllowWindowsUpdateDrivers,
    # Skip the component cleanup (faster, bigger ISO)
    [switch] $SkipComponentCleanup,
    # Keep VBS and Memory Integrity on (more security, a few FPS less)
    [switch] $KeepVBS,
    # Compress Windows files (Compact OS): about 2-3 GB less on disk
    [switch] $CompactOS,
    # Do not delete the work folder at the end
    [switch] $KeepWorkDir
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$KitRoot = $PSScriptRoot

# ---------------------------------------------------------------------------
# Apps to remove (package name prefix). Edit the list as you like.
# Kept: Store, App Installer/winget, Photos, Paint, Notepad, Calculator,
# Snipping Tool, Terminal, Media Player, Xbox.
# ---------------------------------------------------------------------------
$RemoveApps = @(
    'Clipchamp.Clipchamp',
    'Microsoft.549981C3F5F10',              # Cortana
    'Microsoft.BingNews',
    'Microsoft.BingSearch',
    'Microsoft.BingWeather',
    'Microsoft.Copilot',
    'Microsoft.Windows.Copilot',
    'Microsoft.GetHelp',
    'Microsoft.Getstarted',
    'Microsoft.MicrosoftOfficeHub',
    'Microsoft.MicrosoftSolitaireCollection',
    'Microsoft.MicrosoftStickyNotes',
    'Microsoft.MixedReality.Portal',
    'Microsoft.Office.OneNote',
    'Microsoft.OutlookForWindows',
    'Microsoft.People',
    'Microsoft.PowerAutomateDesktop',
    'Microsoft.SkypeApp',
    'Microsoft.StartExperiencesApp',
    'Microsoft.Todos',
    'Microsoft.Wallet',
    'Microsoft.Windows.DevHome',
    'Microsoft.Windows.CrossDevice',
    'Microsoft.WindowsAlarms',
    'Microsoft.WindowsCamera',              # the Deck has no camera
    'MicrosoftWindows.Client.WebExperience', # Widgets
    'Microsoft.WindowsFeedbackHub',
    'Microsoft.WindowsMaps',
    'Microsoft.WindowsSoundRecorder',
    'microsoft.windowscommunicationsapps',  # Mail and Calendar
    'Microsoft.YourPhone',
    'Microsoft.ZuneVideo',
    'MicrosoftCorporationII.MicrosoftFamily',
    'MicrosoftCorporationII.QuickAssist',
    'MicrosoftTeams',
    'MSTeams',
    'Microsoft.Windows.Teams'
)
$XboxApps = @(
    'Microsoft.GamingApp',
    'Microsoft.XboxApp',
    'Microsoft.XboxGameOverlay',
    'Microsoft.XboxGamingOverlay',
    'Microsoft.XboxIdentityProvider',
    'Microsoft.XboxSpeechToTextOverlay',
    'Microsoft.Xbox.TCUI'
)
if ($RemoveXbox) { $RemoveApps += $XboxApps }

# Optional components (Features on Demand) that are useless on a handheld. Removing them is a
# supported servicing operation: cumulative updates keep working.
$RemoveCapabilities = @(
    'App.StepsRecorder',
    'App.Support.QuickAssist',
    'Browser.InternetExplorer',             # Edge IE mode
    'Hello.Face',                           # Windows Hello face: the Deck has no IR camera
    'Language.Handwriting',                 # pen handwriting recognition
    'MathRecognizer',
    'Media.WindowsMediaPlayer',             # legacy Windows Media Player (the new Media Player stays)
    'Microsoft.Wallpapers.Extended',
    'Microsoft.Windows.MSPaint',            # legacy Paint (the new Paint stays)
    'Microsoft.Windows.PowerShell.ISE',
    'Microsoft.Windows.WordPad',
    'Print.Fax.Scan'
)
# Windows features to disable and remove from disk
$RemoveFeatures = @(
    'Recall',
    'WorkFolders-Client',
    'Printing-XPSServices-Features',
    'MicrosoftWindowsPowerShellV2Root',
    'MicrosoftWindowsPowerShellV2',
    'Internet-Explorer-Optional-amd64'
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Write-Step([string]$Message) { Write-Host ''; Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Info([string]$Message) { Write-Host "    $Message" }
function Write-Warn([string]$Message) { Write-Host "    WARNING: $Message" -ForegroundColor Yellow }

function Invoke-Native {
    param([string]$File, [string[]]$Arguments, [switch]$Quiet)
    $ErrorActionPreference = 'Continue'
    if ($Quiet) { $out = & $File @Arguments 2>&1 } else { & $File @Arguments | Out-Host }
    if ($LASTEXITCODE -ne 0) {
        if ($Quiet -and $out) { $out | Out-Host }
        throw "$File exited with code $LASTEXITCODE"
    }
}

function Read-YesNo([string]$Question, [bool]$Default = $true) {
    $hint = if ($Default) { '[Y/n]' } else { '[y/N]' }
    $a = Read-Host "    $Question $hint"
    if ([string]::IsNullOrWhiteSpace($a)) { return $Default }
    return ($a.Trim() -match '^[yYsS]')
}

function Get-WindowsIso {
    # Downloads the official ISO through Fido, the open source tool Rufus uses
    # to get download links straight from Microsoft's servers.
    param([string]$Language, [string]$Destination)
    $ErrorActionPreference = 'Continue'
    $fido = Join-Path $env:TEMP 'Fido.ps1'
    Write-Info 'downloading Fido (the Rufus tool for official ISOs)'
    try {
        Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/pbatard/Fido/master/Fido.ps1' -OutFile $fido -UseBasicParsing -ErrorAction Stop
    } catch { throw "could not download Fido: $($_.Exception.Message)" }
    $sig = Get-AuthenticodeSignature -FilePath $fido
    if ($sig.Status -ne 'Valid') { throw 'Fido.ps1 does not have a valid digital signature' }

    $fidoArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $fido, '-Win', '11', '-Rel', 'Latest', '-Ed', 'Pro', '-Arch', 'x64', '-GetUrl')
    if ($Language) { $fidoArgs += @('-Lang', $Language); $shown = $Language } else { $shown = 'same language as this PC' }
    Write-Info "asking Microsoft for the Windows 11 link ($shown, x64)"
    $out = & powershell.exe @fidoArgs 2>&1
    $url = $out | ForEach-Object { "$_".Trim() } | Where-Object { $_ -match '^https://' } | Select-Object -Last 1
    if (-not $url) { throw "Microsoft did not return a link. Response: $(($out | ForEach-Object { "$_" }) -join ' ')" }

    Write-Info 'downloading the ISO (about 7 GB: time depends on your connection)'
    $partial = "$Destination.part"
    & curl.exe -L --fail --retry 3 --retry-delay 5 -C - -o $partial $url
    if ($LASTEXITCODE -ne 0) { throw "ISO download failed (curl $LASTEXITCODE). Run again: it resumes where it stopped." }
    Move-Item -LiteralPath $partial -Destination $Destination -Force
}

function Set-Reg {
    param([string]$Key, [string]$Name, [string]$Type, [string]$Value)
    $ErrorActionPreference = 'Continue'
    $null = & reg.exe add $Key /v $Name /t $Type /d $Value /f 2>&1
    if ($LASTEXITCODE -ne 0) { Write-Warn "could not set $Key\$Name" }
}

function Remove-RegKey {
    param([string]$Key, [string]$Value)
    $ErrorActionPreference = 'Continue'
    if ($Value) { $null = & reg.exe delete $Key /v $Value /f 2>&1 }
    else        { $null = & reg.exe delete $Key /f 2>&1 }
}

function Disable-OfflineService {
    param([string]$Name)
    $ErrorActionPreference = 'Continue'
    $key = "HKLM\zSYSTEM\ControlSet001\Services\$Name"
    $null = & reg.exe query $key 2>&1
    if ($LASTEXITCODE -eq 0) { Set-Reg $key 'Start' REG_DWORD 4; Write-Info "service disabled: $Name" }
}

$script:LoadedHives = @()
$HiveFiles = @{
    zSOFTWARE = 'Windows\System32\config\SOFTWARE'
    zSYSTEM   = 'Windows\System32\config\SYSTEM'
    zDEFAULT  = 'Windows\System32\config\default'
    zNTUSER   = 'Users\Default\ntuser.dat'
}

function Mount-Hives {
    param([string]$Root, [string[]]$Names)
    $ErrorActionPreference = 'Continue'
    foreach ($n in $Names) {
        $null = & reg.exe load "HKLM\$n" (Join-Path $Root $HiveFiles[$n]) 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Could not load registry hive $n" }
        $script:LoadedHives += $n
    }
}

function Dismount-Hives {
    $ErrorActionPreference = 'Continue'
    [gc]::Collect(); [gc]::WaitForPendingFinalizers(); Start-Sleep -Seconds 1
    foreach ($n in @($script:LoadedHives)) {
        for ($i = 0; $i -lt 5; $i++) {
            $null = & reg.exe unload "HKLM\$n" 2>&1
            if ($LASTEXITCODE -eq 0) { break }
            Start-Sleep -Seconds 2
        }
        if ($LASTEXITCODE -ne 0) { Write-Warn "registry hive $n not unloaded" }
    }
    $script:LoadedHives = @()
}

function Clear-ReadOnly([string]$Path) {
    Get-ChildItem -LiteralPath $Path -Recurse -File -Force | ForEach-Object {
        if ($_.IsReadOnly) { $_.IsReadOnly = $false }
    }
}

# ---------------------------------------------------------------------------
# Initial checks
# ---------------------------------------------------------------------------
if ($PSVersionTable.PSEdition -eq 'Core') {
    throw "Open 'Windows PowerShell' (5.1) as administrator, not PowerShell 7: the classic DISM cmdlets are needed."
}

# Regional settings: same as this PC unless given
if (-not $Locale) { $Locale = (Get-Culture).Name }
if (-not $Locale) { $Locale = 'en-US' }
if (-not $KeyboardLayout) {
    try { $KeyboardLayout = @((Get-WinUserLanguageList)[0].InputMethodTips)[0] } catch { }
    if (-not $KeyboardLayout) { $KeyboardLayout = '0409:00000409' }
}
if (-not $TimeZone) { $TimeZone = (Get-TimeZone).Id }

if (-not $IsoPath -or -not $DriversPath) { Add-Type -AssemblyName System.Windows.Forms }
if (-not $IsoPath) {
    $downloadDir = Join-Path $KitRoot 'Download'
    $isoName = if ($IsoLanguage) { "Win11_$($IsoLanguage -replace '\s', '')_x64.iso" } else { 'Win11_x64.iso' }
    $autoIso = Join-Path $downloadDir $isoName
    if (Test-Path -LiteralPath $autoIso) {
        Write-Host "Using the ISO already downloaded: $autoIso"
        $IsoPath = $autoIso
    } else {
        Write-Host ''
        Write-Host 'The official Windows 11 ISO is needed.'
        if (Read-YesNo "Download it from Microsoft's servers? (about 7 GB; answer n if you already have it)") {
            New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null
            $kitFree = (Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$(Split-Path -Qualifier $downloadDir)'").FreeSpace
            if ($kitFree -lt 8GB) { throw 'At least 8 GB of free space are needed on the kit drive to download the ISO.' }
            try {
                Get-WindowsIso -Language $IsoLanguage -Destination $autoIso
                $IsoPath = $autoIso
            } catch {
                Write-Warn "automatic download failed: $($_.Exception.Message)"
                Write-Warn 'opening the Microsoft page: download the ISO manually, then pick it in the window.'
                Start-Process 'https://www.microsoft.com/software-download/windows11'
            }
        }
    }
}
if (-not $IsoPath) {
    Write-Host 'Pick the Windows 11 ISO in the window that just opened...'
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = 'Pick the Windows 11 ISO'
    $dlg.Filter = 'ISO image (*.iso)|*.iso'
    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { throw 'No ISO selected.' }
    $IsoPath = $dlg.FileName
}
if (-not $DriversPath) {
    Write-Host ''
    Write-Host "Opening Valve's Windows drivers page: download all the Steam Deck OLED drivers"
    Write-Host 'into one folder (zip files are fine), then press ENTER and pick that folder.'
    Start-Process 'https://help.steampowered.com/faqs/view/6121-ECCD-D643-BAA8'
    $null = Read-Host '    ENTER when the drivers are downloaded'
    Write-Host 'Pick the folder with the Valve drivers in the window that just opened...'
    $fb = New-Object System.Windows.Forms.FolderBrowserDialog
    $fb.Description = "Folder with Valve's Steam Deck OLED drivers (zip files are fine)"
    if ($fb.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { throw 'No drivers folder selected.' }
    $DriversPath = $fb.SelectedPath
}
if (-not (Test-Path -LiteralPath $IsoPath))     { throw "ISO not found: $IsoPath" }
if (-not (Test-Path -LiteralPath $DriversPath)) { throw "Drivers folder not found: $DriversPath" }
if ($WorkDir -match '\s') { throw "The work folder path must not contain spaces: $WorkDir" }
foreach ($f in 'autounattend.template.xml', 'Deck-PostInstall.ps1', 'SetupComplete.cmd') {
    if (-not (Test-Path -LiteralPath (Join-Path $KitRoot $f))) { throw "$f is missing from the kit folder" }
}
if ($UserName.Length -gt 20 -or $UserName -match '["/\\\[\]:;|=,+*?<>@]' -or $UserName.Trim() -eq '') {
    throw 'Invalid user name: 20 characters max, no special symbols.'
}
if ($ComputerName.Length -gt 15 -or $ComputerName -notmatch '^[A-Za-z0-9-]+$') {
    throw 'Invalid computer name: 15 characters max, only letters, numbers and hyphens.'
}

if (-not $OutputIso) { $OutputIso = Join-Path $KitRoot 'Win11-SteamDeckOLED.iso' }
$IsoPath     = (Resolve-Path -LiteralPath $IsoPath).Path
$DriversPath = (Resolve-Path -LiteralPath $DriversPath).Path
$OutputIso   = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputIso)
$WorkDir     = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($WorkDir)
$IsoDir   = Join-Path $WorkDir 'iso'
$Mount    = Join-Path $WorkDir 'mount'
$DrvStage = Join-Path $WorkDir 'drivers'
$WorkWim  = Join-Path $WorkDir 'install.wim'

$drive = Split-Path -Qualifier $WorkDir
$free = (Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$drive'").FreeSpace
if ($free -lt 25GB) { throw ('Not enough free space on {0}: {1:N0} GB (at least 25 needed)' -f $drive, ($free / 1GB)) }

$LogFile = [IO.Path]::ChangeExtension($OutputIso, '.log')
Start-Transcript -Path $LogFile -Force | Out-Null
Write-Info "Locale: $Locale  Keyboard: $KeyboardLayout  Time zone: $TimeZone"

$isoMounted = $false
$imageMounted = $false
$success = $false
$started = Get-Date

try {
    # -----------------------------------------------------------------------
    Write-Step 'Preparing the work folder'
    # -----------------------------------------------------------------------
    # Clean up leftovers from a previous attempt
    & {
        $ErrorActionPreference = 'Continue'
        foreach ($n in $HiveFiles.Keys) { $null = & reg.exe unload "HKLM\$n" 2>&1 }
    }
    Get-WindowsImage -Mounted | Where-Object { $_.Path -like "$WorkDir*" } | ForEach-Object {
        Write-Info 'Unmounting an image left over from a previous attempt...'
        Dismount-WindowsImage -Path $_.Path -Discard | Out-Null
    }
    try { Clear-WindowsCorruptMountPoint | Out-Null } catch { }
    if (Test-Path -LiteralPath $WorkDir) { Remove-Item -LiteralPath $WorkDir -Recurse -Force }
    New-Item -ItemType Directory -Path $IsoDir, $Mount, $DrvStage -Force | Out-Null

    # -----------------------------------------------------------------------
    Write-Step 'Copying the ISO contents'
    # -----------------------------------------------------------------------
    $img = Mount-DiskImage -ImagePath $IsoPath -PassThru
    $isoMounted = $true
    $letter = $null
    for ($i = 0; $i -lt 10 -and -not $letter; $i++) {
        $letter = ($img | Get-Volume).DriveLetter
        if (-not $letter) { Start-Sleep -Seconds 1 }
    }
    if (-not $letter) { throw 'The mounted ISO has no drive letter' }
    $null = & robocopy.exe "${letter}:\" $IsoDir /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP
    if ($LASTEXITCODE -ge 8) { throw "Copying the ISO failed (robocopy $LASTEXITCODE)" }
    Dismount-DiskImage -ImagePath $IsoPath | Out-Null
    $isoMounted = $false
    Clear-ReadOnly $IsoDir

    # -----------------------------------------------------------------------
    Write-Step 'Selecting the Windows edition'
    # -----------------------------------------------------------------------
    $srcWim = Join-Path $IsoDir 'sources\install.wim'
    $srcEsd = Join-Path $IsoDir 'sources\install.esd'
    if (Test-Path -LiteralPath $srcWim) { $src = $srcWim }
    elseif (Test-Path -LiteralPath $srcEsd) { $src = $srcEsd }
    else { throw 'The ISO has neither sources\install.wim nor install.esd: is it a Windows 11 ISO?' }

    $images = @(Get-WindowsImage -ImagePath $src)
    $chosen = $images | Where-Object { $_.ImageName -eq "Windows 11 $Edition" } | Select-Object -First 1
    if (-not $chosen) {
        Write-Warn "Edition 'Windows 11 $Edition' not found. Available editions:"
        $images | ForEach-Object { Write-Info ('[{0}] {1}' -f $_.ImageIndex, $_.ImageName) }
        $idx = Read-Host '    Number of the edition to use'
        $chosen = $images | Where-Object { $_.ImageIndex -eq [int]$idx } | Select-Object -First 1
        if (-not $chosen) { throw 'Invalid index' }
    }
    Write-Info "Using: $($chosen.ImageName)"
    Export-WindowsImage -SourceImagePath $src -SourceIndex $chosen.ImageIndex `
        -DestinationImagePath $WorkWim -CompressionType max | Out-Null
    Remove-Item -LiteralPath $src -Force

    # -----------------------------------------------------------------------
    Write-Step 'Mounting the image (a few minutes)'
    # -----------------------------------------------------------------------
    Mount-WindowsImage -ImagePath $WorkWim -Index 1 -Path $Mount | Out-Null
    $imageMounted = $true

    $intl = & dism.exe /English "/Image:$Mount" /Get-Intl
    $m = $intl | Select-String -Pattern 'Default system UI language : ([A-Za-z]{2,3}-[A-Za-z]{2,4})' | Select-Object -First 1
    if ($m) { $UiLang = $m.Matches[0].Groups[1].Value } else { $UiLang = $Locale }
    Write-Info "Image language: $UiLang"

    # -----------------------------------------------------------------------
    Write-Step 'Removing preinstalled apps'
    # -----------------------------------------------------------------------
    foreach ($p in (Get-AppxProvisionedPackage -Path $Mount)) {
        $hit = $RemoveApps | Where-Object { $p.DisplayName -like "$_*" }
        if ($hit) {
            try {
                Remove-AppxProvisionedPackage -Path $Mount -PackageName $p.PackageName | Out-Null
                Write-Info "removed: $($p.DisplayName)"
            } catch { Write-Warn "not removed: $($p.DisplayName)" }
        }
    }

    Write-Step 'Removing optional components that are useless on a handheld'
    foreach ($c in (Get-WindowsCapability -Path $Mount | Where-Object { $_.State -eq 'Installed' })) {
        $hit = $RemoveCapabilities | Where-Object { $c.Name -like "$_*" }
        if ($hit) {
            try {
                Remove-WindowsCapability -Path $Mount -Name $c.Name | Out-Null
                Write-Info "removed: $($c.Name)"
            } catch { Write-Warn "not removed: $($c.Name)" }
        }
    }
    foreach ($f in (Get-WindowsOptionalFeature -Path $Mount)) {
        if ($RemoveFeatures -contains $f.FeatureName -and $f.State -in 'Enabled', 'Disabled') {
            try {
                Disable-WindowsOptionalFeature -Path $Mount -FeatureName $f.FeatureName -Remove -NoRestart | Out-Null
                Write-Info "removed: $($f.FeatureName)"
            } catch { Write-Warn "not removed: $($f.FeatureName)" }
        }
    }

    Write-Info 'removing the OneDrive installer'
    $od = Join-Path $Mount 'Windows\System32\OneDriveSetup.exe'
    if (Test-Path -LiteralPath $od) {
        & {
            $ErrorActionPreference = 'Continue'
            $null = & takeown.exe /f $od 2>&1
            $null = & icacls.exe $od /grant '*S-1-5-32-544:F' 2>&1
        }
        Remove-Item -LiteralPath $od -Force -ErrorAction SilentlyContinue
    }

    # -----------------------------------------------------------------------
    Write-Step "Preparing and injecting Valve's drivers"
    # -----------------------------------------------------------------------
    Copy-Item -Path (Join-Path $DriversPath '*') -Destination $DrvStage -Recurse -Force
    for ($round = 0; $round -lt 3; $round++) {
        $zips = @(Get-ChildItem -LiteralPath $DrvStage -Recurse -Filter *.zip -File)
        if ($zips.Count -eq 0) { break }
        foreach ($z in $zips) {
            $dest = Join-Path $z.DirectoryName $z.BaseName
            Write-Info "extracting $($z.Name)"
            Expand-Archive -LiteralPath $z.FullName -DestinationPath $dest -Force
            Remove-Item -LiteralPath $z.FullName -Force
        }
    }
    Clear-ReadOnly $DrvStage

    $infs = @(Get-ChildItem -LiteralPath $DrvStage -Recurse -Filter *.inf -File |
        Where-Object { Select-String -LiteralPath $_.FullName -Pattern '^\s*\[Manufacturer\]' -Quiet })
    if ($infs.Count -eq 0) {
        Write-Warn 'no .inf driver found: check the drivers folder. Continuing anyway.'
    }
    $ok = 0; $ko = 0
    foreach ($inf in $infs) {
        try {
            Add-WindowsDriver -Path $Mount -Driver $inf.FullName -ErrorAction Stop | Out-Null
            $ok++
        } catch {
            $ko++
            Write-Warn ('driver not injected: {0}' -f $inf.FullName.Substring($DrvStage.Length))
        }
    }
    Write-Info "drivers injected: $ok, not injected: $ko (these are retried after setup)"
    $exes = @(Get-ChildItem -LiteralPath $DrvStage -Recurse -File | Where-Object { $_.Name -in 'setup.exe', 'install.bat' -or $_.Extension -eq '.msi' })
    if ($exes.Count -gt 0) { Write-Info "installers found, to run at first boot: $($exes.Count)" }

    Copy-Item -LiteralPath $DrvStage -Destination (Join-Path $Mount 'DeckDrivers') -Recurse -Force

    # -----------------------------------------------------------------------
    Write-Step 'Adding the setup scripts'
    # -----------------------------------------------------------------------
    $deckSetup = Join-Path $Mount 'DeckSetup'
    $scripts   = Join-Path $Mount 'Windows\Setup\Scripts'
    $pubDesk   = Join-Path $Mount 'Users\Public\Desktop'
    New-Item -ItemType Directory -Path $deckSetup, $scripts, $pubDesk -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $KitRoot 'Deck-PostInstall.ps1') -Destination $deckSetup -Force
    Copy-Item -LiteralPath (Join-Path $KitRoot 'SetupComplete.cmd') -Destination $scripts -Force
    if ($CompactOS) { New-Item -ItemType File -Path (Join-Path $deckSetup 'compactos.flag') -Force | Out-Null }
    $launcher = "@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"C:\DeckSetup\Deck-PostInstall.ps1`"`r`n"
    [IO.File]::WriteAllText((Join-Path $pubDesk 'Steam Deck Setup.cmd'), $launcher, [Text.Encoding]::ASCII)

    # -----------------------------------------------------------------------
    Write-Step 'Applying registry tweaks'
    # -----------------------------------------------------------------------
    Mount-Hives -Root $Mount -Names 'zSOFTWARE', 'zSYSTEM', 'zDEFAULT', 'zNTUSER'
    try {
        # Hardware requirements (the Deck meets them, but avoids blocks if TPM/Secure Boot are off)
        foreach ($v in 'BypassTPMCheck', 'BypassSecureBootCheck', 'BypassRAMCheck', 'BypassStorageCheck', 'BypassCPUCheck') {
            Set-Reg 'HKLM\zSYSTEM\Setup\LabConfig' $v REG_DWORD 1
        }
        Set-Reg 'HKLM\zSYSTEM\Setup\MoSetup' 'AllowUpgradesWithUnsupportedTPMOrCPU' REG_DWORD 1
        foreach ($h in 'zDEFAULT', 'zNTUSER') {
            Set-Reg "HKLM\$h\Control Panel\UnsupportedHardwareNotificationCache" 'SV1' REG_DWORD 0
            Set-Reg "HKLM\$h\Control Panel\UnsupportedHardwareNotificationCache" 'SV2' REG_DWORD 0
        }

        # Local account without network
        Set-Reg 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\OOBE' 'BypassNRO' REG_DWORD 1

        # No automatic disk encryption and no reserved storage (~7 GB)
        Set-Reg 'HKLM\zSYSTEM\ControlSet001\Control\BitLocker' 'PreventDeviceEncryption' REG_DWORD 1
        Set-Reg 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager' 'ShippedWithReserves' REG_DWORD 0

        # Telemetry and privacy
        Set-Reg 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' REG_DWORD 0
        Set-Reg 'HKLM\zSYSTEM\ControlSet001\Services\dmwappushservice' 'Start' REG_DWORD 4
        Set-Reg 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' REG_DWORD 0
        Set-Reg 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' REG_DWORD 0
        Set-Reg 'HKLM\zNTUSER\Software\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection' REG_DWORD 1
        Set-Reg 'HKLM\zNTUSER\Software\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' REG_DWORD 1
        Set-Reg 'HKLM\zNTUSER\Software\Microsoft\InputPersonalization\TrainedDataStore' 'HarvestContacts' REG_DWORD 0

        # Sponsored apps and suggestions
        Set-Reg 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' REG_DWORD 1
        Set-Reg 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableConsumerAccountStateContent' REG_DWORD 1
        Set-Reg 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableCloudOptimizedContent' REG_DWORD 1
        Set-Reg 'HKLM\zSOFTWARE\Policies\Microsoft\PushToInstall' 'DisablePushToInstall' REG_DWORD 1
        $cdm = 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
        foreach ($v in 'ContentDeliveryAllowed', 'FeatureManagementEnabled', 'OemPreInstalledAppsEnabled',
                       'PreInstalledAppsEnabled', 'PreInstalledAppsEverEnabled', 'SilentInstalledAppsEnabled',
                       'SoftLandingEnabled', 'SubscribedContentEnabled', 'SystemPaneSuggestionsEnabled',
                       'SubscribedContent-310093Enabled', 'SubscribedContent-338388Enabled',
                       'SubscribedContent-338389Enabled', 'SubscribedContent-338393Enabled',
                       'SubscribedContent-353694Enabled', 'SubscribedContent-353696Enabled') {
            Set-Reg $cdm $v REG_DWORD 0
        }
        Remove-RegKey "$cdm\Subscriptions"
        Remove-RegKey "$cdm\SuggestedApps"
        Set-Reg 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' REG_DWORD 0

        # Copilot, Recall, widgets, Bing search
        Set-Reg 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' REG_DWORD 1
        Set-Reg 'HKLM\zNTUSER\Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' REG_DWORD 1
        Set-Reg 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' REG_DWORD 1
        Set-Reg 'HKLM\zSOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' REG_DWORD 0
        Set-Reg 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' REG_DWORD 1
        Set-Reg 'HKLM\zSOFTWARE\Policies\Microsoft\Edge' 'HubsSidebarEnabled' REG_DWORD 0

        # Teams, new Outlook, Dev Home: don't reinstall them
        Set-Reg 'HKLM\zSOFTWARE\Policies\Microsoft\Teams' 'DisableInstallation' REG_DWORD 1
        Set-Reg 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Communications' 'ConfigureChatAutoInstall' REG_DWORD 0
        Set-Reg 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Chat' 'ChatIcon' REG_DWORD 3
        Set-Reg 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Mail' 'PreventRun' REG_DWORD 1
        Set-Reg 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate' 'workCompleted' REG_DWORD 1
        Set-Reg 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\OutlookUpdate' 'workCompleted' REG_DWORD 1
        Set-Reg 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\DevHomeUpdate' 'workCompleted' REG_DWORD 1
        Remove-RegKey 'HKLM\zSOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate'
        Remove-RegKey 'HKLM\zSOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\DevHomeUpdate'

        # OneDrive
        Set-Reg 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\OneDrive' 'DisableFileSyncNGSC' REG_DWORD 1
        Remove-RegKey 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Run' 'OneDriveSetup'

        # UI for a 7.4" screen: compact taskbar, automatic touch keyboard
        Set-Reg 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Search' 'SearchboxTaskbarMode' REG_DWORD 0
        Set-Reg 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowTaskViewButton' REG_DWORD 0
        Set-Reg 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarMn' REG_DWORD 0
        Set-Reg 'HKLM\zNTUSER\Software\Microsoft\TabletTip\1.7' 'EnableDesktopModeAutoInvoke' REG_DWORD 1

        # Gaming: no background recording (costs CPU and battery). Game Bar still works.
        Set-Reg 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' REG_DWORD 0
        Set-Reg 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'HistoricalCaptureEnabled' REG_DWORD 0

        # Services that are useless on the Deck (telemetry, removed Maps, retail demo, fax)
        foreach ($svc in 'DiagTrack', 'MapsBroker', 'RetailDemo', 'Fax') { Disable-OfflineService $svc }

        # Game performance: VBS and Memory Integrity cost FPS on the Deck's APU
        if (-not $KeepVBS) {
            Set-Reg 'HKLM\zSYSTEM\ControlSet001\Control\DeviceGuard' 'EnableVirtualizationBasedSecurity' REG_DWORD 0
            Set-Reg 'HKLM\zSYSTEM\ControlSet001\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled' REG_DWORD 0
        }

        # RAM (16 GB shared with the GPU): Edge does not stay loaded in the background
        Set-Reg 'HKLM\zSOFTWARE\Policies\Microsoft\Edge' 'StartupBoostEnabled' REG_DWORD 0
        Set-Reg 'HKLM\zSOFTWARE\Policies\Microsoft\Edge' 'BackgroundModeEnabled' REG_DWORD 0
        Set-Reg 'HKLM\zSOFTWARE\Policies\Microsoft\Edge' 'HideFirstRunExperience' REG_DWORD 1

        # Battery and network: updates come from Microsoft only, no upload to other PCs
        Set-Reg 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' REG_DWORD 0

        # Console-like experience
        Set-Reg 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Personalization' 'NoLockScreen' REG_DWORD 1          # no lock screen
        Set-Reg 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\EdgeUI' 'AllowEdgeSwipe' REG_DWORD 0                # edge swipes don't open panels while gaming
        Set-Reg 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'NoAutoRebootWithLoggedOnUsers' REG_DWORD 1  # no forced reboots while playing
        Set-Reg 'HKLM\zNTUSER\Control Panel\Accessibility\StickyKeys' 'Flags' REG_SZ '506'                     # no Sticky Keys popup
        Set-Reg 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_IrisRecommendations' REG_DWORD 0
        Set-Reg 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'Start_AccountNotifications' REG_DWORD 0

        # Windows Update does not replace Valve's drivers with generic ones
        if (-not $AllowWindowsUpdateDrivers) {
            Set-Reg 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' 'ExcludeWUDriversInQualityUpdate' REG_DWORD 1
        }
    } finally {
        Dismount-Hives
    }

    if (-not $SkipComponentCleanup) {
        Write-Step 'Cleaning up image components (10-30 minutes, it may look stuck: that is normal)'
        Invoke-Native dism.exe @('/English', "/Image:$Mount", '/Cleanup-Image', '/StartComponentCleanup', '/ResetBase')
    }

    # -----------------------------------------------------------------------
    Write-Step 'Saving and compressing the image (10-20 minutes)'
    # -----------------------------------------------------------------------
    Dismount-WindowsImage -Path $Mount -Save | Out-Null
    $imageMounted = $false
    $finalEsd = Join-Path $IsoDir 'sources\install.esd'
    Invoke-Native dism.exe @('/English', '/Export-Image', "/SourceImageFile:$WorkWim", '/SourceIndex:1',
        "/DestinationImageFile:$finalEsd", '/Compress:recovery', '/CheckIntegrity')
    Remove-Item -LiteralPath $WorkWim -Force

    # -----------------------------------------------------------------------
    Write-Step 'Removing hardware checks from the installer too'
    # -----------------------------------------------------------------------
    $bootWim = Join-Path $IsoDir 'sources\boot.wim'
    $bootIdx = @(Get-WindowsImage -ImagePath $bootWim).Count
    Mount-WindowsImage -ImagePath $bootWim -Index $bootIdx -Path $Mount | Out-Null
    $imageMounted = $true
    Mount-Hives -Root $Mount -Names 'zSYSTEM'
    try {
        foreach ($v in 'BypassTPMCheck', 'BypassSecureBootCheck', 'BypassRAMCheck', 'BypassStorageCheck', 'BypassCPUCheck') {
            Set-Reg 'HKLM\zSYSTEM\Setup\LabConfig' $v REG_DWORD 1
        }
    } finally {
        Dismount-Hives
    }
    Dismount-WindowsImage -Path $Mount -Save | Out-Null
    $imageMounted = $false

    # -----------------------------------------------------------------------
    Write-Step 'Creating the unattended setup file'
    # -----------------------------------------------------------------------
    $xmlText = [IO.File]::ReadAllText((Join-Path $KitRoot 'autounattend.template.xml'), [Text.Encoding]::UTF8)
    $values = [ordered]@{
        '{{UILANG}}'       = $UiLang
        '{{LOCALE}}'       = $Locale
        '{{KEYBOARD}}'     = $KeyboardLayout
        '{{TIMEZONE}}'     = $TimeZone
        '{{COMPUTERNAME}}' = $ComputerName
        '{{USERNAME}}'     = $UserName
        '{{PASSWORD}}'     = $Password
    }
    foreach ($k in $values.Keys) {
        $xmlText = $xmlText.Replace($k, [System.Security.SecurityElement]::Escape([string]$values[$k]))
    }
    $null = [xml]$xmlText   # make sure the XML is valid
    [IO.File]::WriteAllText((Join-Path $IsoDir 'autounattend.xml'), $xmlText, (New-Object Text.UTF8Encoding $false))

    # -----------------------------------------------------------------------
    Write-Step 'Creating the ISO'
    # -----------------------------------------------------------------------
    $arch = $env:PROCESSOR_ARCHITECTURE.ToLower()
    $adkOscdimg = "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\$arch\Oscdimg\oscdimg.exe"
    if (Test-Path -LiteralPath $adkOscdimg) {
        $oscdimg = $adkOscdimg
        Write-Info 'using oscdimg from the installed Windows ADK'
    } else {
        $oscdimg = Join-Path $WorkDir 'oscdimg.exe'
        Write-Info "downloading oscdimg.exe from Microsoft's servers"
        Invoke-WebRequest -Uri 'https://msdl.microsoft.com/download/symbols/oscdimg.exe/3D44737265000/oscdimg.exe' `
            -OutFile $oscdimg -UseBasicParsing
        # The copy on Microsoft's symbol server is old and often has no embedded signature.
        # It comes over HTTPS from msdl.microsoft.com, so checking it is a Microsoft executable is enough.
        $item = Get-Item -LiteralPath $oscdimg
        $head = [IO.File]::ReadAllBytes($oscdimg)[0..1]
        $sig = Get-AuthenticodeSignature -FilePath $oscdimg
        $signedOk = ($sig.Status -eq 'Valid' -and $sig.SignerCertificate.Subject -match 'Microsoft')
        $looksOk = ($head[0] -eq 0x4D -and $head[1] -eq 0x5A -and $item.Length -gt 50KB -and
                    $item.VersionInfo.CompanyName -match 'Microsoft')
        if (-not $signedOk -and -not $looksOk) {
            throw 'The downloaded oscdimg.exe does not look valid. Install the Windows ADK (Deployment Tools only) and try again.'
        }
        if (-not $signedOk) { Write-Info 'oscdimg.exe has no embedded signature (old build) but came from Microsoft over HTTPS: using it' }
    }
    $efiBin = Join-Path $IsoDir 'efi\microsoft\boot\efisys_noprompt.bin'   # boots without "press any key"
    if (-not (Test-Path -LiteralPath $efiBin)) { $efiBin = Join-Path $IsoDir 'efi\microsoft\boot\efisys.bin' }
    $etfs = Join-Path $IsoDir 'boot\etfsboot.com'
    if (Test-Path -LiteralPath $OutputIso) { Remove-Item -LiteralPath $OutputIso -Force }
    Invoke-Native $oscdimg @('-m', '-o', '-u2', '-udfver102', '-lDECK_WIN11',
        "-bootdata:2#p0,e,b$etfs#pEF,e,b$efiBin", $IsoDir, $OutputIso) -Quiet

    $success = $true
    $size = (Get-Item -LiteralPath $OutputIso).Length / 1GB
    $mins = [int]((Get-Date) - $started).TotalMinutes
    Write-Host ''
    Write-Host ('DONE in {0} minutes: {1} ({2:N1} GB)' -f $mins, $OutputIso, $size) -ForegroundColor Green
    Write-Host ''
    Write-Host 'Next steps:'
    Write-Host '  1. Write the ISO to a USB stick with Rufus (GPT partition scheme, UEFI target).'
    Write-Host '     In the Rufus "Windows User Experience" dialog untick everything: it is already built in.'
    Write-Host '  2. Deck powered off: hold Volume Down and press Power, then pick the USB stick.'
    Write-Host '  3. At the disk step delete ALL partitions of the internal drive, then Next.'
    Write-Host '  4. If asked for a product key choose "I don''t have a product key".'
    Write-Host '  The setup script starts by itself at first sign-in.'
}
catch {
    Write-Host ''
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Details in the log: $LogFile"
    Write-Host "The work folder $WorkDir was kept: do not run Build-ISO.cmd again before reading the README (Troubleshooting)."
    throw
}
finally {
    if ($script:LoadedHives.Count -gt 0) { Dismount-Hives }
    if ($imageMounted) {
        Write-Info 'Unmounting the image without saving...'
        Dismount-WindowsImage -Path $Mount -Discard -ErrorAction SilentlyContinue | Out-Null
    }
    if ($isoMounted) { Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue | Out-Null }
    if ($success -and -not $KeepWorkDir -and (Test-Path -LiteralPath $WorkDir)) {
        Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    Stop-Transcript | Out-Null
}
