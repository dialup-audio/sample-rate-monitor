# kHz Display

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

Download the latest zip from [Releases](https://github.com/dialup-audio/khz-display/releases), unzip, and drag the app to Applications. To start it at login, add it under System Settings → General → Login Items.

## Build from source

Needs Xcode command line tools, CMake and Ninja.

```bash
make        # builds into build/
make run
```

## Settings

The alert rate is stored in the app's standard macOS preferences, nothing else is written to disk:

```bash
defaults read audio.dialup.khz-display alertRate      # e.g. 96000
defaults delete audio.dialup.khz-display              # reset
```

Choosing **Off** in the menu clears it too.

## Updates

Once a launch, the app asks GitHub whether a newer release exists and only speaks up if there is one; turn this off with **Check for Updates on Startup** in the app's menu, and the app makes no network requests at all. **Check for Updates Now** does the same on demand and always tells you the result. Nothing is downloaded or installed automatically: the Download button opens the product page on dialup.audio. These checks are the only network requests the app makes. The same menu has **Help** and **Report an Issue**, which open the project pages on dialup.audio.
