# Sample Rate Display

Your audio interface's sample rate, in the macOS menubar. Always. The actual number.

<!-- screenshot: menubar item, normal + red alert state -->

Free tools by [dialup.audio](https://dialup.audio).

## What it does

- Shows the sample rate of your default output device (`96 kHz`, `44.1 kHz`, ...) and updates the instant it changes.
- **Set sample rate to…** switches the device to any rate it supports.
- **Alert if not…** turns the menubar item red when the device is running at anything other than the rate you chose. Something changed your rate? You see it immediately.
- The device name is shown in the menu.

That's it. Standard macOS menu, no settings window, no daemon.

## Philosophy

- **It shows the number.** Not a badge, not a status dot. If something keeps flipping your interface between 96 and 48 every few seconds, you'll watch it happen.
- **It doesn't fight other apps.** Some apps (Serato, LosslessSwitcher, DAWs) change the sample rate on their own. Auto-reverting just starts a fight, and your audio loses. This app tells you and gets out of the way.
- **Works with any interface.** It talks to Core Audio directly. No driver software, no scraping another app's window, no permissions.
- **Small.** One source file you can read in a few minutes.

## Install

Download the latest zip from [Releases](https://github.com/dialup-audio/sample-rate-display/releases), unzip, and drag the app to Applications. To start it at login, add it under System Settings → General → Login Items.

## Build from source

Needs Xcode command line tools, CMake and Ninja.

```bash
make        # builds into build/
make run
```

## Settings

The alert rate is stored in the app's standard macOS preferences, nothing else is written to disk:

```bash
defaults read audio.dialup.khzdisp alertRate      # e.g. 96000
defaults delete audio.dialup.khzdisp              # reset
```

Choosing **Off** in the menu clears it too.

## Updates

The app never touches the internet on its own. **Check for Updates…** asks GitHub whether a newer release exists and, if so, offers to open the release page. Nothing is downloaded or installed automatically. That click is the only network request the app makes.
