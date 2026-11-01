@echo off
rem Double-click: unblocks the kit files and starts the ISO build as administrator.
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath '%~dp0.' -Recurse | Unblock-File; Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -NoExit -File \"%~dp0Build-DeckWin11.ps1\"'"
