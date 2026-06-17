# AnalogTV – Quick Start Guide

Welcome to **AnalogTV**. This is a hardware wrapper around FieldStation42:
https://github.com/shane-mason/FieldStation42
Full documentation, installation guide, and channel configuration walkthroughs are at:
https://fieldstation42.com

This document explains how to connect to the device, add new content, and maintain the system.

Here is a video showing my method of building one of these.
https://www.youtube.com/watch?v=RRlkJXp7n9o

Use balena etcher to restore full disk image of **AnalogTV** for Raspberry pi 3 or 4 set to composite out with full Fieldstation 42 configuration:
https://mega.nz/file/GawhSBiK#dxtKwH1jwKpJ0B-27t4GbPmxci7goJrAl5I0F-0sW_4
Disk image will require a 16gb sd card or larger

This disk image defaults to composite out and will NOT output anything on HDMI until videoOutToggle.sh is run.

## 1. Network & Login

### Wi-Fi

AnalogTV will try to connect to this Wi-Fi network automatically:

- **SSID:** `AnalogTV`
- **Password:** `analogwaves`

Make sure this Wi-Fi network exists and is in range.

### SSH Access

- **Username:** `analog`
- **Password:** `waves`

The easiest way to connect is by hostname:

ssh analog@analogtv.local

#### On macOS / Linux

1. Make sure you are on the same network as AnalogTV.
2. Open Terminal.
3. Run:

ssh analog@analogtv.local

4. When prompted, type the password:

waves

#### On Windows

**Option A – Windows 10/11 with built-in OpenSSH:**

1. Make sure you are on the same network as AnalogTV.
2. Open Command Prompt or PowerShell.
3. Run:

ssh analog@analogtv.local

4. Enter the password:

waves

**Option B – Using PuTTY (if OpenSSH is not available):**

1. Download PuTTY from the official site and install it.
2. Open PuTTY.
3. In the Host Name field, enter:

analogtv.local

4. Set port to `22`, connection type `SSH`, then click **Open**.
5. When prompted for username, enter `analog`, then password `waves`.

## 2. Using the AnalogTV Control Menu

Once logged in via SSH, run:

AnalogTV

This opens a menu of options for maintaining your AnalogTV system, including:

- Scanning new files and rebuilding the catalog
- Adjusting channel schedules (day / week / month)
- Fixing `confs/`, `catalog/`, `scripts/` symlinks
- Programming or clearing the FLIRC remote
- Joining a new Wi-Fi network

Use the on-screen prompts to select and confirm actions.

## 3. Safely Powering Off and Removing the USB Drive

To add or change content, always shut down AnalogTV safely:

1. On the front of the AnalogTV unit, press and hold the power (on/off) button until the system shuts down.
2. Wait until the device is fully off (no activity LEDs from the Pi / device).
3. Gently remove the USB drive from the back of the unit.
4. Plug the USB drive into your computer.

## 4. Adding Content from YouTube with yt-dlp

To keep all content at 480p or lower, use `yt-dlp`, a free command-line downloader.

### Installing yt-dlp

#### On macOS (with Homebrew)

1. Install Homebrew if you don’t have it.
2. In Terminal, run:

brew install yt-dlp

#### On Windows (simple method)

1. Download the `yt-dlp.exe` release from the official project page.
2. Save it somewhere convenient, for example:

C:\yt-dlp\yt-dlp.exe

3. Optionally, add that folder to your PATH so you can run `yt-dlp` from any directory.

Alternatively, on Windows with Python installed:

python -m pip install yt-dlp

### Downloading at 480p (or below) with audio

Use this command format to download from YouTube at 480p or below with H.264 video and audio. The container format does not matter:

yt-dlp -f "bestvideo[height<=480][vcodec*=avc1]+bestaudio/best[height<=480][vcodec*=avc1]" -o "%(title)s.%(ext)s" "<YOUTUBE_URL>"

Replace `<YOUTUBE_URL>` with the actual video link.

**Example:**

yt-dlp -f "bestvideo[height<=480][vcodec*=avc1]+bestaudio/best[height<=480][vcodec*=avc1]" -o "%(title)s.%(ext)s" "[https://www.youtube.com/watch?v=dQw4w9WgXcQ](https://www.youtube.com/watch?v=dQw4w9WgXcQ)"

All downloaded files should be placed into the appropriate channel folder, for example:

X:\catalog\<ChannelName>\main\

(where `X:` is the drive letter of the USB stick on your computer).

## 5. Re-inserting the USB Drive and Updating AnalogTV

After you finish adding content:

1. Safely eject the USB drive from your computer.
2. Plug the USB drive back into the AnalogTV unit.
3. Toggle the power switch on the AnalogTV power cable to turn the system back on.
4. Wait for it to boot.

Then, either:

### Via SSH

1. Connect with:

ssh analog@analogtv.local

2. Run:

AnalogTV

3. Choose the option to “Scan new files and rebuild catalog”.
4. After the catalog rebuild completes, reboot the device if prompted (or via the menu).

### Via Web Interface (if available)

If you have a management web UI configured:

1. Open the AnalogTV web interface in your browser.
2. Use the option to rebuild/scan the catalog.
3. Reboot the device once the rebuild is done.

Rebuilding the catalog lets AnalogTV find your new files and update the schedules. A reboot ensures all channels pick up the latest content correctly.

## 6. Using the Rear Rebuild / Reboot Button

AnalogTV has a small button on the back of the unit that can be used for quick maintenance without logging in.

This button is useful after new media has been added to the USB catalog.

### Rebuild Catalog and Reboot

Press the rear button **twice**.

AnalogTV will automatically:

1. Rebuild each station.
2. Update the catalog.
3. Reboot the machine.

This is the fastest way to make newly added media available after placing files into the correct catalog folders.

### Reboot Only

Press the rear button **three times**.

AnalogTV will reboot without rebuilding the stations or catalog.

### Optional: Watching the Rebuild Process Over SSH

The rebuild process happens automatically in the background. It is not normally visible on screen.

To watch the rebuild progress, connect by SSH and run:

```bash
~/FieldStation42/scripts/gpioStatus.sh
