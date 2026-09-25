# Schedule Maker

A Godot 4.6 Android app that turns your schedule and assignment due dates into your phone wallpaper.

- **Schedule**: items that repeat on chosen days or happen once on a date.
- **Due Dates**: assignments with notes and a countdown.
- **Wallpaper**: each day's wallpaper shows that day's schedule and what's due soon. It updates by itself just after midnight.

## Install on your phone

1. On your Android phone, open **[the latest release](../../releases/latest)** and tap **ScheduleMaker.apk**.
2. Open the downloaded file. If Android asks, allow installing apps from your browser.
3. Open Schedule Maker, add your schedule, then go to **Wallpaper → Set as wallpaper now**.

## How the APK is built

Every push to `main` runs `.github/workflows/build-apk.yml`, which builds the wallpaper plugin in `android_plugin/`, exports the Godot project, signs it with the key in the repo secrets (`KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEYSTORE_ALIAS`), and publishes a release.
