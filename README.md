# Dash Cam

## Execute flutter app in the emulator
```bash
# list available emulators
flutter emulators

# launch emulator
# flutter emulators --launch <emulator id>
flutter emulators --launch dashcam_api36

# build and run project
flutter run
```

## Execute in Phone
```bash
flutter devices

# flutter run -d <device-id>
flutter run -d ZLM7AU4PMNOFUOUW
```

## Exit app and close the emulator

1. Press q in running terminal
2. Enter `adb emu kill` in the terminal or use emulator close (x) button to exit emulator