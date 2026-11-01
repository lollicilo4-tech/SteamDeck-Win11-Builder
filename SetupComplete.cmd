@echo off
rem ---------------------------------------------------------------------
rem  Run by Windows as SYSTEM at the end of setup,
rem  before the first sign-in. Machine-wide settings.
rem ---------------------------------------------------------------------
set LOG=%SystemDrive%\DeckSetup\setupcomplete.log
echo [%date% %time%] SetupComplete started >> "%LOG%"

rem Hibernation and fast startup off: frees space equal to the RAM (16 GB)
powercfg /hibernate off >> "%LOG%" 2>&1

rem Install every Valve driver copied into the image on the devices present
if exist "%SystemDrive%\DeckDrivers" pnputil /add-driver "%SystemDrive%\DeckDrivers\*.inf" /subdirs /install >> "%LOG%" 2>&1

rem Telemetry scheduled tasks
schtasks /Change /TN "Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser" /Disable >> "%LOG%" 2>&1
schtasks /Change /TN "Microsoft\Windows\Application Experience\ProgramDataUpdater" /Disable >> "%LOG%" 2>&1
schtasks /Change /TN "Microsoft\Windows\Customer Experience Improvement Program\Consolidator" /Disable >> "%LOG%" 2>&1
schtasks /Change /TN "Microsoft\Windows\Customer Experience Improvement Program\UsbCeip" /Disable >> "%LOG%" 2>&1
schtasks /Change /TN "Microsoft\Windows\Windows Error Reporting\QueueReporting" /Disable >> "%LOG%" 2>&1

rem Compact OS (only if requested with -CompactOS): compresses system files
if exist "%SystemDrive%\DeckSetup\compactos.flag" compact /compactos:always >> "%LOG%" 2>&1

echo [%date% %time%] SetupComplete finished >> "%LOG%"
exit /b 0
