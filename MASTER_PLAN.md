# Dash Cam - Implementation Master Plan
This is the master plan for implementing dash cam (DashCam) system. Always follow plan items. Once competed a plan item, mark it as completed using [x] mark. Do not attend to completed items if not specifically asked so

DashCam is an android application that enables our personal phone to use as a dash cam. Once application is running (recording is started), it should continuously record using pre-configured camera. The default camera is back camera. See below Plan Items for the detail explanation of each development scope

## Plan Items

1. [x] First implement a simple screen with a button to start capturing (`Start` button) . Once the button is pressed, start recording and writing to a file in the default location. We will setup file location later. In the screen provide a view to see capturing video content. Also, include a button to stop capturing `Stop` button.
2. [x] Allow file location configurable and the file captured accessible by the phone user. To make file location configurable add a new screen (`Settings` screen). In Settings screen, allow the user to configure file location. So, in app level now we should have two screens. This `Settings` screen and the `Capture` screen we developed in Plan Item 1. The default screen should be Capture screen. Provide a menu so that user can navigate to the `Settings` screen. When in `Settings` screen, user should be able to navigate to `Capture` screen by using the same menu
3. [x] Fix below issues
    - [x] Fix preview aspect ratio (stretch + sideways framing)
    - [x] Stop pinning the window to landscape; let the app follow the device instead
          (`android:screenOrientation="fullSensor"`, which also ignores the system auto-rotate lock).
          Landscape remains fully supported but is no longer enforced.
    - [x] Rebuild and verify preview in landscape on emulator
4. [x] Above issue fixes fixed most of the issues including stretch problem. However if the emulator is positioned in portrait orientation still I have to move to right side for it to show me. Otherwise, it shows only a half of me. Landscape orientation is okay
    - **Fixed. The stretch and the sideways/offset framing are gone, and the "only half of me" portrait
      symptom does not occur on real hardware.**
    - Root cause of the original bug: `android:screenOrientation="landscape"` pinned the window, but
      `CameraPreview` derives its aspect ratio and rotation from the *device* orientation. In portrait the
      two disagreed, so the `Texture` was stretched into a landscape box and `BoxFit.cover` cropped most of
      the frame away.
    - Fix: `AndroidManifest.xml` is `fullSensor` (app follows the device, ignores the auto-rotate lock) so
      the window and the plugin's notion of orientation can no longer disagree. `_previewSize` in
      `lib/capture_screen.dart` now derives the preview box from `controller.value.deviceOrientation` —
      the same value `CameraPreview` uses internally — and is driven by a `ValueListenableBuilder` so it
      tracks rotation live. `BoxFit.cover` is kept in both orientations.
    - **The residual ~50% portrait crop is an EMULATOR-ONLY artifact, not a platform limit.** Verified on a
      real arm64 phone (Redmi 25078RA3EA, Android 16, MediaTek `mtkcam` HAL): the preview shows the full
      field of view in both portrait and landscape, and no Dart-side change was needed. Do not treat this
      as a CameraX/rotation bug, and do not try to work around it.
    - The strongest evidence that the difference is the camera implementation and not our code: on the
      real phone `logcat configureStreams` reports the **same** stream configuration as the emulator —
      preview `1280x720 GPU_TEXTURE`, `1280x720 BLOB`, `1280x720 YCBCR_420_888` — with the same CameraX
      and the same Dart, yet there is no crop. Only the camera HAL underneath differs.
    - Why the emulator still shows it (recorded so nobody re-derives this on the emulator):
      - `logcat` `configureStreams:19` in portrait shows the preview, image-analysis and image-capture
        streams all still `1280x720`, so the full sensor frame does reach CameraX.
      - `Preview(...)` is constructed with **no** `targetRotation`
        (`camera_android_camerax-0.7.5/lib/src/android_camera_camerax.dart:407-410`), so it inherits
        CameraX's default and follows the display rotation. On the emulator's camera implementation the
        `Preview` use case centre-crops the 16:9 frame to the portrait display aspect before writing the
        SurfaceTexture; on real hardware it does not.
      - `lockCaptureOrientation` (`android_camera_camerax.dart:569-584`) only pins `imageCapture`,
        `imageAnalysis` and `videoCapture`; there is **no Dart API to pin the preview's target rotation**.
        This is moot now that no crop is observed on real devices.
      - The Flutter layout was never at fault: the portrait preview area is `411.4 x 644.2` logical
        (aspect `0.6386`) and the preview child is `720 x 1280` (aspect `0.5625`), so `BoxFit.cover`
        scales by width and shows 100% of the child width. A temporary magenta `ColoredBox` behind the
        `FittedBox` rendered zero visible pixels, ruling out letterboxing.
      - Measured FOV against a control-stable landscape pair (control correlation `0.9908`, full-width
        match `0.1012`): the best match is **50% of frame width**, spanning frame `x=28%..78%` and
        centred within 3% of the frame centre.
    - Verified: `flutter analyze` clean; portrait and landscape both record valid `1280x720` MP4s on the
      emulator and on real hardware; no debug instrumentation left in `lib/`.
    - Follow-up (not a DashCam bug): a recorded `1280x720` clip is 16:9 and a phone held in landscape is
      ~2.2:1, so it plays fullscreen in landscape with small bars. If a specific player refuses to
      go fullscreen, suspect that player or a portrait-only system rotation lock, not the file — the MP4
      is properly finalized (it has a `moov` atom) and a landscape recording carries no rotate hint.
    - Recorded-file facts from the real phone (single portrait clip, ~10.5s): `ftyp=isom`, video-only
      (no audio track), `avc1` **High profile Level 3.1**, `1280x720`, 30.01 fps, ~9.3 Mbps,
      `moov` present and `mdat` ends exactly at EOF (finalised correctly). Note 9.3 Mbps is high for
      720p and High profile is less universally decodable than Baseline/Main; if player compatibility
      ever becomes a requirement, cap it via `MediaSettings.videoBitrate` (the plugin reads it at
      `android_camera_camerax.dart:424`). There is no Dart API to force the H.264 profile.
    - Recordings are **always coded 1280x720 with no rotation hint**, including clips recorded while the
      phone was held in portrait. Whether the frames themselves are rotated cannot be determined from
      the container alone — it needs decoding — so treat "a portrait clip plays landscape" as unverified.
      The `fullSensor` activity also means the app ignores the system rotation lock, while other apps
      (video players) do not.
5. [x] Rework the Capture screen layout so the camera preview gets the space it needs, and fix the
     Start/Stop buttons moving under the user's finger. Found while testing on a real phone; not a
     regression, but it makes landscape — the natural dash-cam orientation — the worst case.
    - **Problem 1 — landscape preview is squeezed to ~35% of frame height.** Measured on the phone
      (Redmi 25078RA3EA, landscape 1600x720 @320dpi = 800x360 logical): app bar occupies y=0..89
      logical and the controls block y=246..360, leaving a preview area of only **800x157 logical
      (aspect 5.1)**. With the 1280x720 preview child and `BoxFit.cover` that scales by width and
      crops vertically, so roughly **65% of the recorded frame height is invisible in the preview**.
      Portrait is far better (~87% visible). The controls and app bar together consume ~56% of the
      landscape height, so the preview cannot show what is actually being recorded.
    - **Problem 2 — Start/Stop jump 88px (~44 logical).** `_buildControls` in `lib/capture_screen.dart`
      renders the "last saved" filename row conditionally (`capture_screen.dart:334`) *below* the button
      row, inside a `Column` that is bottom-anchored by the `Expanded` preview above it. When that row
      appears or disappears the whole controls block reflows, so the buttons move (measured `y=496` with
      a filename shown, `y=584` without). This caused a real missed Stop tap during automated testing,
      and a user aiming at Stop as recording stops will miss too.
    - Goals: give the preview the largest practical area in both orientations; keep Start/Stop in a
      fixed, predictable position; keep the recording indicator visible at all times; keep the last-saved
      filename discoverable; keep the Settings drawer reachable.
    - Proposed approach — **float the controls over the preview** (the standard camera-app idiom, as used
      by the native camera apps): preview becomes the full background, Start/Stop become circular
      icon-only buttons over it, and the status line + filename become overlaid text rather than rows in
      a bottom column. This fixes Problem 2 structurally — absolutely positioned buttons cannot reflow —
      and reclaims essentially all of the ~114 logical control height. NOTE: open decision, see below.
    - Constraints: tap targets must stay >= 48x48 logical for accessibility (so icon-only buttons save
      width, not height — the height win comes from overlaying, not from dropping the labels); must not
      regress the preview framing fix from item 4 (the `_previewSize` / `BoxFit` logic stays as is);
      the filename text must not be clipped; dark scrim or gradient is needed for legibility over bright
      scene content.
    - **Open decisions to settle before implementing:**
      - Overlaid controls (maximum preview, controls sit on top of the video) vs a slimmer bottom bar
        (nothing over the video, but the preview stays noticeably shorter).
      - Whether the controls should auto-hide while recording, and whether a tap-to-toggle is wanted.
      - Whether the AppBar should also be slimmed or overlaid — it still costs ~89 logical in landscape.
      - Whether icon-only is acceptable: the record-dot and stop-square glyphs are universal, but if
        icon-only is rejected the overlay layout still delivers the height win.
    - Verification: re-measure the preview area from `uiautomator` bounds in both orientations before and
      after, and recompute the visible-height fraction; confirm the Start/Stop bounds are byte-identical
      across idle -> recording -> saved transitions; visually confirm on the real phone. Emulator
      measurements are valid for layout only, not for camera behaviour.
    - Progress (layout rework done in `lib/capture_screen.dart`, not yet signed off):
      - Controls now float over a full-bleed preview. The `Scaffold` no longer has an `appBar`; a compact
        scrim-backed top strip carries the menu + title, and a scrim-backed bottom strip carries the
        status, Start/Stop and the saved label. `BoxFit.cover` and the `_previewSize` logic from item 4
        are untouched. Note the `Builder` around the `Stack` is required — `Scaffold.of` needs a context
        below the `Scaffold` for `openDrawer`.
      - Start/Stop are now icon-only circular buttons at 56x56 (record = red, stop = white), which is
        the camera-app convention and keeps the tap target above the 48x48 accessibility minimum.
      - **Problem 2 verified fixed on the real phone in landscape:** Start and Stop stayed at
        `[674,536][786,648]` and `[834,536][946,648]` across recording -> stopped -> saved (was an 88px
        jump). The fixed-height `_buildSavedLabel` slot is what guarantees this.
      - **Problem 1 verified fixed for landscape:** preview area went from `800x157` to the full
        `800x360` logical, so visible frame height rose from ~35% to **~80%**.
      - **Portrait regression from the full-bleed change — RESOLVED and verified.** The full-bleed
        Stack initially made the portrait preview full-height (`360x800` logical, aspect 0.45) against a
        `720x1280` frame (aspect 0.5625), so `cover` switched to scaling by *height* and portrait showed
        100% height but only ~80% of the width, where before it had 100% width and ~93% height.
        Fixed by `_previewFit()`, which picks the fit from the **geometry of the box versus the frame**
        rather than from the orientation: when the box is relatively taller than the frame it returns
        `BoxFit.contain` (portrait letterboxes and shows the whole frame, keeping the horizontal field of
        view that matters on a dash cam — adjacent lanes, oncoming traffic); otherwise it returns
        `BoxFit.cover` (landscape fills the screen and only crops vertically). Geometry rather than
        `deviceOrientation` is deliberate, so it cannot disagree with `_previewSize` and is
        rotation-proof. Needs a `LayoutBuilder` to read the incoming box.
      - **Portrait verified on the real phone.** `_previewFit` returning `contain` predicts 160 px
        letterbox bands top and bottom with a 1280 px content height on the 720x1600 screen. Measured by
        diffing three `screencap` frames ~1.4 s apart and taking, per row, the max temporal delta across
        several x-strips: live content occupies exactly **y=160..1439 = 1280 px**, with 160 px bands above
        and below. (Two 4-5 px runs at y=47-56 are Android's pulsing camera-in-use privacy indicator —
        delta ~3.5 versus 26-33 for real video — not preview content.) **Do not try to measure this by
        brightness:** the room is dark enough that dark scene pixels and letterbox bars are
        indistinguishable in a single screenshot, and the static overlay widgets sit on top of both
        bands. The temporal-delta method is immune to both problems and is the one to reuse.
      - Landscape is unchanged by `_previewFit` (the box is relatively wider than the frame there, so it
        still takes `cover`), and the earlier landscape verification still holds: full-bleed `800x360`
        preview with ~80% visible frame height, and Start/Stop pinned at `[674,536][786,648]` /
        `[834,536][946,648]` across recording -> stopped -> saved.

6. [x] Reduce recorded file size without a visible quality loss
   - Problem: recordings are far larger than they need to be. Measured on the real phone, item 4's
     files are `1280x720` @ `30.01` fps, `avc1` **High Profile Level 3.1**, averaging
     **~9.1-9.3 Mbps** (e.g. 59,987,210 B over 52.953 s = 9.06 Mbps). A 30-second clip costs ~35 MB and
     the test folder filled to ~192 MB in about 40 minutes of use. 9.3 Mbps is roughly 2-4x more than
     720p30 needs; it is wasted on this content, not a quality requirement.
   - Constraints: keep `1280x720` (visible detail loss below that is unacceptable); keep 30 fps;
     keep audio disabled (already the case, so there is no audio saving to claim); must not regress
     item 4's preview/rotation behaviour; the file must stay valid and playable.
   - Available levers, in order of impact:
     - **`videoBitrate` — the whole fix.** `CameraController` takes `videoBitrate` directly
       (`camera-0.12.1/lib/src/camera_controller.dart:247-262`) and the plugin passes it straight to
       `Recorder(targetVideoEncodingBitRate:)` (`android_camera_camerax.dart:423`). It reaches the
       MediaCodec encoder as a target, so a ~72x lower target yields roughly a proportional file-size
       drop and is a single named argument in `_setupCamera`.
     - **`ResolutionPreset` — do not use for this.** It moves the *recording* resolution via
       `VideoQuality` (`android_camera_camerax.dart:1606-1631`); `high` = `HD` = the 720p we want,
       dropping to `medium`/`low` = `SD` = a visible downgrade.
     - **`fps` — not recommended.** `fps` pins a `CameraIntegerRange` on preview/image/video
       (`android_camera_camerax.dart:393-425`). 30 -> 24 saves only ~20% and costs motion detail, which
       is the one thing a dash cam must not lose.
     - **H.264 profile — no API.** Item 4 already established there is no Dart-level control over the
       encoder profile, so High -> Main/Baseline (which would shrink files at equal quality) is not
       reachable.
   - Proposed approach: add `videoBitrate:` to the single `CameraController(...)` in `_setupCamera`.
     **One constant, one line, both orientations** — the same controller drives the preview and both
     orientations, so no per-orientation handling and no new settings UI is needed.
   - Bitrate choice (**decide before implementing**):
     - `4000000` (~4 Mbps) — ~57% smaller, loss effectively invisible. Safest.
     - `2500000` (~2.5 Mbps) — ~73% smaller, in line with what 720p30 streaming services use.
       **Recommended**; the first visible cost is fine detail in fast motion (sign text, number plates).
     - `2000000` (~2 Mbps) — ~78% smaller; usable for dash-cam review, softer on motion detail.
     - `1500000` or lower — blockiness in high-motion scenes; too aggressive, listed only to bound it.
   - Verification: record the *same* scene at the chosen bitrate, confirm the byte size drops roughly in
     proportion, re-parse the MP4 to confirm it is still valid (`moov` present, `mdat` to EOF, still
     `1280x720`/30fps), and watch a motion-heavy clip for blocking. Use a realistic drive-by-motion
     sample, not a static scene — VBR spends far fewer bits on a still frame, so a static test will
     flatter the result.
   - Follow-up (deliberately NOT in this item, do not build unasked): a quality selector in Settings
     (Low/Medium/High) would be the natural next step once a single bitrate is proven.
   - **RESULT: works. Measured ~66% smaller, still 720p30 High L3.1.**
     - Chosen `2500000`, achieved **3.16 Mbps** (`dashcam_20260930_123942.mp4`, 8,465,505 B over 21.459 s)
       against 9.06 / 9.34 / 9.44 Mbps before. The 1.26x overshoot over target is normal VBR behaviour
       on live video; a still frame would land closer to target, so do not judge this from a static clip.
       Per 30 s: ~35 MB -> ~11.9 MB.
     - Confirmed the bitrate genuinely reaches CameraX, not a coincidence: grepping logcat for CameraX's
       own `"Using fallback VIDEO bitrate"` string returns **0 occurrences**, and the fallback path in
       `VideoEncoderConfigDefaultResolver.get()` is only taken when `VideoSpec.getBitrate()` is 0.
       Chain: `CameraController(videoBitrate:)` -> `MediaSettings.videoBitrate`
       (`camera_platform_interface-2.14.0/.../method_channel/method_channel_camera.dart:106`) ->
       `Recorder(targetVideoEncodingBitRate:)` (`android_camera_camerax.dart:423`) -> native
       `builder.setTargetVideoEncodingBitRate(int)` (`RecorderProxyApi.java:36-43`) -> `VideoSpec.bitrate`.
       CameraX 1.6.2, verified by javap against the AAR in the Gradle cache.
     - **Correcting an earlier false negative in this item:** a first sample
       (`dashcam_20260930_121409.mp4`) measured 9.44 Mbps and looked like the argument was being ignored,
       implying the MediaTek encoder was at fault. That was wrong. That clip was only 8.231 s and the
       device rotated mid-recording, which reconfigured the encoder, so it was not a clean comparison.
       The MediaTek encoder honours `KEY_BIT_RATE` after all. Do not resurrect the "encoder ignores the
       bitrate" theory without a clean, rotation-free measurement.
     - Remaining caveat: the *visual* cost is subjective and still needs the user's eyes on a
       motion-heavy clip (the first thing to degrade is fine detail during fast motion — sign text and
       number plates). Lowering the target further is possible but trades visible sharpness, so 2.5 Mbps
       is the recommended setting; revisit only with feedback that quality is unacceptable.
