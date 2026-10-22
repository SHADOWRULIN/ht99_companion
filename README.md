# HT99 Companion

A Flutter Android companion app for the HT99 / WWfit smartwatch. This repository is a community companion project, not an official WWfit app.

## Build

Requirements: Flutter/Dart, Java 17, Android SDK, and an Android device with BLE.

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

The current MediaTek implementation requires `android/app/src/main/jniLibs/armeabi-v7a/libCommand.so` from a WWfit APK you are legally allowed to use. This is a 32-bit ARM library; the Gradle ABI filter is intentionally limited to `armeabi-v7a`. Do not rename it or invent an arm64 binary.

## What is currently wired

- HT99 BLE discovery, connection, and standard battery characteristic where available.
- MediaTek native protocol initialization, `REQV` version handshake, command framing, and serialized write-with-response transport.
- Phone Current Time and Time Format GATT profiles used by the original WWfit app.
- Best-effort native time synchronization and 12/24-hour setting.
- Watch notification and weather command paths using native framing.
- Health request commands for step count, heart rate, blood pressure, temperature, and the firmware's pedometer stream. Data tiles only update after a recognizable reply; missing values remain `--`.
- Find-watch via the standard Immediate Alert characteristic and find-phone alarm on the handset.

## Known limitations

- Watch-face upload is not active. A valid dial file is MD5-checked, but actual file transfer still requires porting the original MediaTek FOTA manager and confirming firmware acknowledgements. The app does not send guessed dial packets.
- Watch alarms and water reminders are kept in the app only until their exact write formats and acknowledgement behaviour are verified.
- Sleep, oxygen saturation, and other proprietary health values depend on whether this watch firmware reports a supported response. The app must not fabricate readings.
- A successful BLE write is not the same as confirmation that the watch applied the setting. Verify changes on the physical watch.

## Privacy

Weather is fetched over HTTPS from Open-Meteo. Notification access is optional and must be enabled by the user in Android's Notification Access settings. Notification text is sent only while the watch is connected and the matching package is enabled in the app.
