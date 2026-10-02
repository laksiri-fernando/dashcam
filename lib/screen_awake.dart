import 'package:flutter/services.dart';

/// Keeps the display awake while a recording is running.
///
/// Plan item 7. The screen timing out pauses the Flutter app, and the Capture
/// screen responds to `AppLifecycleState.paused` by closing the camera and
/// finalising the recording — so an untouched phone quietly ends a recording that
/// the user never stopped. Holding `FLAG_KEEP_SCREEN_ON` on the activity window
/// stops the timeout happening in the first place.
///
/// This deliberately does nothing about the user pressing the power button: that
/// pauses the app for real, and ending the recording there is the intended
/// behaviour. Surviving a manual lock would need a foreground service, which is a
/// much larger change than this item.
class ScreenAwake {
  static const _channel = MethodChannel('dashcam/screen');

  /// Whether [set] failures should be swallowed.
  ///
  /// A failed call only means the screen may dim during a long recording, which
  /// is not worth interrupting the user over, so this deliberately ignores errors.
  static Future<void> set(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setKeepScreenOn', <String, Object?>{
        'enabled': enabled,
      });
    } on PlatformException {
      // Nothing to recover: recording carries on either way.
    } on MissingPluginException {
      // Non-Android platform, nothing to hold awake.
    }
  }
}
