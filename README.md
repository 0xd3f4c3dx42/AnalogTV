# AnalogTV – Quick Start Guide
AnalogTV – Quick Start Guide

Welcome to AnalogTV. This document explains how to connect to the device, add new content, and maintain the system.

1. Network & Login
Wi-Fi

AnalogTV will try to connect to this Wi-Fi network automatically:

SSID: AnalogTV

Password: analogwaves

Make sure this Wi-Fi network exists and is in range.

SSH Access

Username: analog

Password: waves

The easiest way to connect is by hostname:

ssh analog@analogtv.local

On macOS / Linux

Make sure you are on the same network as AnalogTV.

Open Terminal.

Run:

ssh analog@analogtv.local


When prompted, type the password:

waves

On Windows

Option A – Windows 10/11 with built-in OpenSSH:

Make sure you are on the same network as AnalogTV.

Open Command Prompt or PowerShell.

Run:

ssh analog@analogtv.local


Enter the password:

waves


Option B – Using PuTTY (if OpenSSH is not available):

Download PuTTY from the official site and install it.

Open PuTTY.

In the Host Name field, enter:

analogtv.local


Set port to 22, connection type SSH, then click Open.

When prompted for username, enter analog, then password waves.

2. Using the AnalogTV Control Menu

Once logged in via SSH, run:

AnalogTV


This opens a menu of options for maintaining your AnalogTV system, including:

Scanning new files and rebuilding the catalog

Adjusting channel schedules (day / week / month)

Fixing confs/catalog/scripts symlinks

Programming or clearing the FLIRC remote

Joining a new Wi-Fi network

Use the on-screen prompts to select and confirm actions.

3. Safely Powering Off and Removing the USB Drive

To add or change content, always shut down AnalogTV safely:

On the front of the AnalogTV unit, press and hold the power (on/off) button until the system shuts down.

Wait until the device is fully off (no activity LEDs from the Pi / device).

Gently remove the USB drive from the back of the unit.

Plug the USB drive into your computer.

4. Adding Content from YouTube with yt-dlp

To keep all content at 480p or lower, use yt-dlp, a free command-line downloader.

Installing yt-dlp
On macOS (with Homebrew)

Install Homebrew if you don’t have it.

In Terminal, run:

brew install yt-dlp

On Windows (simple method)

Download the yt-dlp.exe release from the official project page.

Save it somewhere convenient, for example C:\yt-dlp\yt-dlp.exe.

Optionally, add that folder to your PATH so you can run yt-dlp from any directory.

Alternatively, on Windows with Python installed:

python -m pip install yt-dlp

Downloading at 480p (or below) with audio

Use this command format to download from YouTube at 480p or below with H.264 video and audio. The container format does not matter:

yt-dlp -f "bestvideo[height<=480][vcodec*=avc1]+bestaudio/best[height<=480][vcodec*=avc1]" -o "%(title)s.%(ext)s" "<YOUTUBE_URL>"


Replace <YOUTUBE_URL> with the actual video link.

Example:

yt-dlp -f "bestvideo[height<=480][vcodec*=avc1]+bestaudio/best[height<=480][vcodec*=avc1]" -o "%(title)s.%(ext)s" "https://www.youtube.com/watch?v=XXXXXXXXXXX"


All downloaded files should be placed into the appropriate channel folder, for example:

X:\catalog\<ChannelName>\main\


(where X: is the drive letter of the USB stick on your computer).

5. Re-inserting the USB Drive and Updating AnalogTV

After you finish adding content:

Safely eject the USB drive from your computer.

Plug the USB drive back into the AnalogTV unit.

Toggle the power switch on the AnalogTV power cable to turn the system back on.

Wait for it to boot.

Then, either:

Via SSH

Connect with:

ssh analog@analogtv.local


Run:

AnalogTV


Choose the option to “Scan new files and rebuild catalog”.

After the catalog rebuild completes, reboot the device if prompted (or via the menu).

Via Web Interface (if available)

If you have a management web UI configured:

Open the AnalogTV web interface in your browser.

Use the option to rebuild/scan the catalog.

Reboot the device once the rebuild is done.

Rebuilding the catalog lets AnalogTV find your new files and update the schedules. A reboot ensures all channels pick up the latest content correctly.
