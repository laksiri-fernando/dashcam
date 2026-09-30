# AGENTS.md

## Project state

Flutter app `dashcam` (Android-only so far). `MASTER_PLAN.md` is the source of truth for scope —
read it before starting work, and mark items `[x]` when done. Do not build anything listed as
Deferred there.

Plan items 1 and 2 are implemented. There is nothing beyond that.

- `lib/main.dart` — `DashCamApp`, sets `CaptureScreen` as `home` (the default screen)
- `lib/capture_screen.dart` — the whole capture UI: permission request, camera setup, preview,
  Start/Stop, lifecycle handling. This is where most changes go.
- `lib/settings_screen.dart` — pick/clear the recording destination folder
- `lib/app_drawer.dart` — the shared menu + app bar; the drawer is set on each `Scaffold`, not
  on the `AppBar` (there is no `AppBar.drawer`)
- `lib/storage_location.dart` — the `StorageLocation` model, the `dashcam/storage` MethodChannel
  calls, and the `SharedPreferences` entry
- `lib/video_store.dart` — the single seam for *where recordings are written*. Keep storage
  concerns here; the capture UI should not learn paths.
- `android/app/src/main/kotlin/com/example/dashcam/MainActivity.kt` — native SAF implementation
  behind the `dashcam/storage` channel
- Android id: `com.example.dashcam` (`android/app/build.gradle.kts:8,19`) — still the example id
- `ios/ web/ windows/ macos/ linux/` are generated but unconfigured/untested; only `android/` works
- `pubspec.yaml` description is still "A new Flutter project"

## Commands

```bash
flutter analyze                 # lint + typecheck; passes clean
dart format lib test            # NOTE: there is no `flutter format` subcommand
flutter build apk --debug       # verified working (~12s warm)
flutter run                     # after launching the emulator below
```

Run `flutter analyze` after edits — it is the only automated check that works here.

## Camera preview aspect ratio and orientation

`controller.value.previewSize` / `aspectRatio` are reported in the **sensor's landscape**
orientation (e.g. `Size(1280, 720)`), but `CameraPreview` derives its aspect ratio *and* its
rotation from `controller.value.deviceOrientation` — not from `MediaQuery`. So the preview box has
to be derived from that same value or the two disagree. `_buildPreview` in `lib/capture_screen.dart`
does this in `_previewSize` (swapping the size unless the orientation is
`DeviceOrientation.landscapeLeft`/`landscapeRight`), wrapped in a `ValueListenableBuilder` so it
tracks rotation live, and lays it out with `FittedBox(fit: BoxFit.cover)`, which fills the space
without ever distorting.

The activity is **not** pinned to landscape: `android:screenOrientation="fullSensor"` in
`android/app/src/main/AndroidManifest.xml` makes the window follow the device (and ignore the system
auto-rotate lock). That is deliberate. The old `"landscape"` lock is what caused the original bug —
window forced landscape while the plugin rendered for the physical portrait device, so the texture was
stretched and `BoxFit.cover` cropped most of the frame away. Do not reintroduce it.

**Portrait shows a reduced field of view ON THE EMULATOR ONLY — this is an emulator camera artifact, not
a layout bug and not a CameraX/platform limit.** On a real arm64 phone the preview shows the full frame
in both portrait and landscape (verified). On the x86_64 AOSP emulator, portrait shows only the central
~50% of the frame width. `Preview` is constructed with no `targetRotation`
(`camera_android_camerax-0.7.5/lib/src/android_camera_camerax.dart:407-410`), so it follows the display
rotation and the emulator's implementation centre-crops the 16:9 frame to the portrait aspect before it
reaches the SurfaceTexture. `lockCaptureOrientation` (`:569-584`) pins only imageCapture /
imageAnalysis / videoCapture, so there is no Dart API to change it. **Do not try to fix this in the
widget tree and do not describe it as a platform limitation** — verify camera/preview behaviour on real
hardware before drawing conclusions. Full evidence in `MASTER_PLAN.md` item 4.

**Verifying preview geometry from a screenshot is unreliable.** Dark regions in the webcam scene
look identical to letterbox bars. To tell them apart, temporarily put a bright `ColoredBox`
*behind* the `FittedBox`: any visible colour means the box is letterboxing, none means it covers.
A border drawn *around* the `CameraPreview` is useless — the texture renders on top of it.

## `flutter test` is BROKEN on this machine — not a code bug

Every `flutter test` fails while *loading* the test file:

```
An Application Control policy or security policy has blocked execution.
ProcessException: An Application Control policy has blocked this file
  (../../runtime/bin/process_win.cc:579)
```

Windows WDAC / Application Control blocks
`C:\src\flutter\bin\cache\artifacts\engine\windows-x64\flutter_tester.exe`, which is the runner
`flutter test` uses. **`flutter analyze`, `flutter build apk`, and running on the emulator all work
normally.** If a test run fails, check for this error before touching the test code. Real
widget-test verification has to happen on the emulator (or the policy must allow-list `C:\src\flutter`).

## Emulator

One AVD: **`dashcam_api36`** — API 36 (Android 16), x86_64, **AOSP "default" image (no Google Play
services)**, Pixel 7 profile. WHPX hardware acceleration is available.

```bash
flutter emulators                              # lists the Id column; use it, don't guess names
flutter emulators --launch dashcam_api36
flutter run                                    # then q in this console to quit
adb emu kill                                   # graceful emulator shutdown + quick-boot snapshot
```

Notes:
- `emulator.exe` is at `%LOCALAPPDATA%\Android\Sdk\emulator\emulator.exe`, **not** under
  `C:\src\flutter`. `flutter emulators --launch dashcam_api36` is the safer way to start it.
- The AVD's camera is the **host laptop webcam** (`hw.camera.back=webcam0`), which is what makes
  preview and recorded video verifiable. `emulated` also works but generates a near-static
  synthetic frame — measured at *exactly* 0.0 pixel difference across the whole preview over
  800ms except one small patch, which looks like "only some colours moving" in the saved file.
  Real webcam content costs ~255 KB/s vs ~64 KB/s for the synthetic image.
- **Changing any `config.ini` value invalidates the quick-boot snapshot**, so the next boot is
  cold and app state can revert to an older `userdata` image. App settings that look like they
  "un-apply" themselves after a config change are a snapshot artifact, not a persistence bug —
  re-verify with `adb shell run-as com.example.dashcam cat shared_prefs/FlutterSharedPreferences.xml`.
- The AVD name is arbitrary (`dashcam_api37` etc. would work as a *label*), but no API 37 system
  image exists in Google's repo, so an actual API 37 AVD cannot be created.
- `adb` is **not on PATH**; it lives at
  `C:\Users\admin\AppData\Local\Android\Sdk\platform-tools\adb.exe`
- Never force-kill `emulator.exe` — it skips the snapshot and can leave a stale lock file.
- **The emulator's camera is not representative.** Its webcam-backed `hw.camera.back` crops the preview
  in portrait (see the camera section above). Anything concluded about preview framing, field of view or
  rotation **must be confirmed on the real phone** before it is treated as a finding.

## Running on a real phone (USB debugging)

The user's arm64 phone works and is the authoritative check for anything camera-related.

```bash
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" devices -l   # want state: device
flutter run -d <device-id>                                          # -d: emulator may also be up
```

- The phone must show `device`, not `unauthorized` — tap **Allow** on the "Allow USB debugging?" dialog
  and tick "Always allow from this computer". `unauthorized`/`offline` means replug; nothing listed at
  all means a charge-only cable or a missing Windows OEM driver.
- The first build on real hardware is a full rebuild (arm64 vs the emulator's x86_64); expect minutes.
- Grant CAMERA on first launch, and set the destination folder in Settings before recording.
- Debug builds attach to the Dart VM, so they feel sluggish; `flutter run --release` or install
  `build\app\outputs\flutter-apk\app-release.apk` for real use. Press `q` to detach — the app keeps
  running on the device.
- Recordings pulled from a SAF folder under shared storage need **no root**:
  `adb pull /sdcard/Download/dashcam_<stamp>.mp4 .` Root is only needed for app-private paths.

## `sdkmanager` is BROKEN — install system images manually

The new SDK Manager CLI delegates to a native library that the same Application Control policy
blocks:

```
UnsatisfiedLinkError: C:\Users\admin\.android\cli\bundles\<hash>\lib\downloader_jni.dll:
An Application Control policy has blocked this file
```

So `sdkmanager install` cannot be used. To add a system image:

1. Read `https://dl.google.com/android/repository/sys-img/android/sys-img2-3.xml` and find the
   `remotePackage` (x86_64 images: API 36 `x86_64-36_r02.zip`, 805 MB, SHA1
   `829c076e8ff448a336097ae25a355b495ba36e2c`).
2. Download from `https://dl.google.com/android/repository/sys-img/android/<url>`.
3. Verify the SHA1 from the manifest, then extract into
   `%ANDROID_SDK%\system-images\android-<api>\default\x86_64\`.
4. The SDK tools regenerate `package.xml` on the next run, so the image registers correctly.
5. Create the AVD: `avdmanager create avd -n <name> -k "system-images;android-36;default;x86_64" -d pixel_7 --force`

`avdmanager` itself works (pure Java) — only `sdkmanager`'s download path is blocked.
Cosmetic warning to ignore: `cmdline-tools;latest` actually lives in `cmdline-tools\latest-2`.

## Toolchain paths

- Flutter SDK: `C:\src\flutter` (3.47.5 stable, Dart 3.13.4)
- Android SDK: `C:\Users\admin\AppData\Local\Android\Sdk` (platform 36, build-tools 36.0.0)
- JDK: `C:\Program Files\Microsoft\jdk-21.0.12.101-hotspot`, set via `flutter config --jdk-dir`.
  `JAVA_HOME` is empty and `java` on PATH is **11** — misleading, ignore it. Android/Gradle need 17+.
- `flutter doctor` is green for the Android toolchain. Its only complaint is missing Visual Studio,
  which is irrelevant to Android.

## Conventions / gotchas

- `analysis_options.yaml` excludes `android/**`, `ios/**`, `web/**`, `windows/**`, `macos/**`,
  `linux/**` from analysis. `flutter analyze` therefore **never checks native platform code** —
  verify Android Gradle/Kotlin changes by actually building.
- `lib/main.dart:17` uses Dart **dot-shorthand** (`.fromSeed(...)`). This is valid Dart 3.10+
  syntax, not a typo — do not "fix" it.
- No CI workflows, no lint task runner, no pre-commit hooks.
- Git: only one commit (`a86c8e8 Initial commit`, README/.gitignore). Everything else — including
  `lib/`, `android/`, `pubspec.yaml` — is **untracked**. `.idea/` and `dashcam.iml` are Android
  Studio leftovers that are untracked and *not* in `.gitignore`; the user works in VS Code.
  Stage deliberately and don't commit IDE files by accident.

## Android plugin gotcha: `permission_handler` must stay on 12.x

`permission_handler` 13/14 pulls `permission_handler_android` 14.1.0, which hardcodes
`compileSdk = 37`. This SDK only has platform **36** (Flutter's `flutter.compileSdkVersion` is 36),
so the build dies with:

```
Could not determine the dependencies of task ':permission_handler_android:compileDebugJavaWithJavac'.
> Failed to find target with hash string 'android-37'
```

`permission_handler_android` 13.0.1 (used by `permission_handler` 12.x) uses `compileSdk 35` and
works. That is why `pubspec.yaml` pins `permission_handler: 12.0.3` exactly rather than `^`. Do not
"upgrade" it without checking the resolved `permission_handler_android` compileSdk in
`%LOCALAPPDATA%\Pub\Cache\hosted\pub.dev\permission_handler_android-*\android\build.gradle`.

Note `camera_android_camerax` correctly uses `flutter.compileSdkVersion`, so `camera` is fine.

## Verifying UI changes on the emulator without tests

`flutter test` is blocked, so UI behaviour is verified by driving the running app with adb. Flutter
publishes a semantics tree that `uiautomator` can read, which gives exact bounds and the current
state — far more reliable than guessing coordinates or trying to view screenshots:

```bash
adb shell am start -n com.example.dashcam/.MainActivity
adb shell uiautomator dump /sdcard/ui.xml
adb shell cat /sdcard/ui.xml     # node bounds=[x1,y1][x2,y2] + content-desc/state
adb shell input tap <center-x> <center-y>
```

The buttons sit at `[42,2096][524,2222]` (Start) and `[556,2096][1038,2222]` (Stop) on the
1080x2400 Pixel 7 profile; re-dump rather than trusting that if the layout changes.

Reading recorded files back needs root, because on the emulator they are app-private:

```bash
adb root
adb pull /data/user/0/com.example.dashcam/app_flutter/dashcam_<stamp>.mp4 .
adb unroot
```

On a real phone, recordings in a shared-storage SAF folder pull without root — see the physical device
section above.

Never pipe adb binary output through PowerShell `>` or `Out-File` — it corrupts the bytes. Use
`adb shell screencap -p <remote>` + `adb pull`.

## Native Android code is invisible to `flutter analyze`

`android/**` is excluded from analysis, so Kotlin errors only appear at build time — and
`flutter build` hides the actual message. To see it, run Gradle directly and set JAVA_HOME, or it
picks the JDK 11 that is on PATH and refuses to start:

```bash
$env:JAVA_HOME="C:\Program Files\Microsoft\jdk-21.0.12.101-hotspot"
.\gradlew.bat :app:compileDebugKotlin --console=plain   # run from android/
```

## Folder picker: Android blocks some folders

The SAF picker will not let the user select the root of internal storage, nor the `Download` root —
those show "Can't use this folder. To protect your privacy, choose another folder" and leave
`USE THIS FOLDER` **disabled** (`enabled="false"` in the uiautomator dump). The user has to go one
level deeper, or tap `CREATE NEW FOLDER`. This is platform behaviour, not a bug in the app.

When automating the picker through adb, the flow is: drawer → Settings → Change folder → tap a
folder row → `CREATE NEW FOLDER` if needed → `USE THIS FOLDER` (only enabled once you are deep
enough) → `ALLOW` on the confirmation dialog. Files are written into the chosen folder directly,
not into a `DashCam` subfolder.

## Working Rules for Open Code
- For All developments refer MASTER_PLAN.md
- ALWAYS present a plan and confirm key assumptions before writing code
  (validate-before-implement).
- Work within one task per change-set where possible.
- Never commit secrets, keys/, or *.pem. 
- Do NOT implement anything listed as Deferred in MASTER_PLAN.md
