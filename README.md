# Slay the Spire 2 for Android (unofficial port)

Play your own copy of **Slay the Spire 2** offline on an Android phone, with touch controls.

This repo contains only the port's own code. It has **no game files**: your PC builds the phone files from your
Steam install. You need to own the game. Unofficial fan project, not affiliated with or endorsed by Mega Crit;
no warranty. Please don't share game files.

**Tested with:** STS2 **v0.111.0** (commit `41cef1ea`), on a Pixel 9a (Android 17). Other game versions may not work.

## Install (about 20 minutes, mostly copying)

You need Slay the Spire 2 on Steam (Windows PC) and a 64-bit Android phone (Android 7+, about 3 GB free).

1. On the phone: Settings > About phone > tap *Build number* 7 times, then Developer options > turn on *USB debugging*.
2. On the PC: on this page click Code > Download ZIP, and unzip it.
3. Plug the phone in and double-click **install.cmd** in the unzipped folder.
   It installs what's missing (Python, .NET 9, Android tools), finds your Steam copy of the game, downloads the
   latest app, and copies everything to the phone. Accept "Allow USB debugging" on the phone when asked.
4. Open **Slay the Spire 2** on the phone. The first start takes about 20 seconds.

Notes: Windows may ask permission while installing the tools. Windows may also warn about the downloaded script
(More info > Run anyway). Without a cable (Android 11+): turn on Developer options > *Wireless debugging* and pair it with
`adb pair <ip:port> <code>` and `adb connect <ip:port>` first; the PC and phone must be on the same network.

## Updating

- **Port updates** (touch fixes and so on): install [Obtainium](https://github.com/ImranR98/Obtainium) on the phone and add
  this repo's URL. It installs new releases over the old app and keeps your saves.
- **After a new Slay the Spire 2 version:** double-click **install.cmd** again.

## Controls

| Action | Gesture |
|---|---|
| Click | Tap |
| Play a card | Drag it onto an enemy or the play area (a tap only highlights it) |
| Inspect | Long-press |
| Pick a card, relic or shop item | Tap to inspect, then tap the confirm tick at the right edge |
| Back | Back button or gesture (opens the pause menu) |

Settings that don't apply on a phone are greyed out and marked "(not on Android)".

## Good to know

- The app has no internet permission: nothing leaves your phone.
- The game saves when you leave the app, and *Continue* resumes after Android closes it.
- Rare crashes can happen in long sessions; your run is saved first.
- Report problems via [Issues](https://github.com/HowieYHY/STS2-android-emulator/issues).

Developer notes, test records and build instructions: [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).
