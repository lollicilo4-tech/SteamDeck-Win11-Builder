# Changelog

## v1.1

- **Resume mode:** if a build stops after the Windows image is finished (for example while creating the ISO), running Build-ISO.cmd again offers to create only the ISO instead of starting over.
- **90 Hz by default:** the first-boot script sets the Deck OLED screen to 90 Hz, so 45 and 90 FPS caps pace evenly.
- **Cleaner progress:** DISM's progress bar stays on one line instead of printing a new line for every percentage.
- **Better free-space check:** when the ISO is downloaded to the same drive as the build, the script checks for the space both need (about 33 GB).
- README: 90 Hz tip, resume mode in Troubleshooting, changelog link.

## v1.0

- First public release: official ISO download via Fido, Valve OLED drivers injected, debloat, handheld tweaks, unattended setup, first-boot script (drivers, screen rotation, Wi-Fi, Steam, Handheld Companion, Lossless Scaling, Big Picture).
