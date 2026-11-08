# Slay the Spire 2 for Android (unofficial port)

Play your own copy of **Slay the Spire 2** offline on an Android phone, with touch controls.

This repo contains only the port's own code. It has **no game files**: your PC builds the phone files from your
Steam install. You need to own the game. Unofficial fan project, not affiliated with or endorsed by Mega Crit;
no warranty. Please don't share game files.

**Tested with:** STS2 **v0.111.0** (commit `41cef1ea`), on a Pixel 9a (Android 17). Other game versions may not work.

## What you need

- Slay the Spire 2 on Steam (Windows PC)
- A 64-bit Android phone (Android 7+, about 3 GB free)
- On the PC: Python 3, the .NET 9 SDK and Android platform-tools
  (`winget install Python.Python.3.12 Microsoft.DotNet.SDK.9 Google.PlatformTools`)

## Install (about 20 minutes)

1. On the phone: Settings → About phone → tap *Build number* 7 times, then Developer options → turn on *USB debugging*.
2. Download the newest `sts2port-…-arm64.apk` from [Releases](https://github.com/HowieYHY/STS2-android-emulator/releases/latest),
   and the source (Code → Download ZIP).
3. Plug the phone in, accept "Allow USB debugging", and in the source folder run:

   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts\push-game.ps1 -GameDir "<Steam>\steamapps\common\Slay the Spire 2" -Apk <downloaded apk> -InstallApk
   ```

4. Open **Slay the Spire 2** on the phone. The first start takes about 20 seconds.

No cable? On Android 11+, use Developer options → *Wireless debugging* → *Pair device with pairing code*, then
`adb pair <ip:port> <code>` and `adb connect <ip:port>`, and run step 3. The PC and phone must be on the same network.

## Updating

- **Port updates** (touch fixes and so on): install [Obtainium](https://github.com/ImranR98/Obtainium) on the phone and add
  this repo's URL. It installs new releases over the old app and keeps your saves.
- **After a new Slay the Spire 2 version:** run step 3 again from the PC.

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
