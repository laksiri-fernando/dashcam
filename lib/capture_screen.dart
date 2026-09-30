import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app_drawer.dart';
import 'storage_location.dart';
import 'video_store.dart';

enum _Phase { starting, idle, recording, error }

/// Plan item 1: live camera preview plus Start and Stop controls that write
/// the recording to a file.
class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen>
    with WidgetsBindingObserver {
  /// Plan item 6. `ResolutionPreset.high` alone has the encoder target roughly
  /// 9 Mbps for 720p30, which is 2-4x more than this footage needs. 2.5 Mbps
  /// is in line with what 720p30 streaming services use and cuts files by ~73%,
  /// with the first visible cost limited to fine detail during fast motion.
  static const int _videoBitrate = 2500000;

  late final VideoStore _store = VideoStore(StorageLocationStore());

  CameraController? _controller;
  _Phase _phase = _Phase.starting;
  String? _error;
  bool _permissionBlocked = false;
  SavedRecording? _lastSaved;
  Duration _elapsed = Duration.zero;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_openCamera());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    unawaited(_controller?.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      // Holding the camera in the background is what a dash cam must avoid
      // doing unknowingly, so give the device back its camera here.
      unawaited(_closeCamera());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_openCamera());
    }
  }

  Future<void> _openCamera() async {
    setState(() {
      _phase = _Phase.starting;
      _error = null;
    });

    try {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        _fail(
          'Camera permission was not granted.',
          blocked: status.isPermanentlyDenied,
        );
        return;
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        _fail('No camera was found on this device.');
        return;
      }

      // The plan calls for the back camera; fall back to whatever exists.
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        videoBitrate: _videoBitrate,
      );
      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _permissionBlocked = false;
        _phase = _Phase.idle;
      });
    } on CameraException catch (e) {
      _fail(_describe(e), blocked: e.code == 'CameraAccessDeniedWithoutPrompt');
    } catch (e) {
      _fail('$e');
    }
  }

  Future<void> _closeCamera() async {
    _ticker?.cancel();
    final controller = _controller;
    _controller = null;
    if (controller == null) return;

    // Close out a recording that is still running so the file is not lost.
    if (controller.value.isRecordingVideo) {
      try {
        final recording = await controller.stopVideoRecording();
        await _store.save(recording);
      } on CameraException {
        // Best effort: the camera is going away regardless.
      }
    }
    await controller.dispose();

    if (!mounted) return;
    setState(() {
      _phase = _Phase.starting;
      _elapsed = Duration.zero;
    });
  }

  Future<void> _start() async {
    final controller = _controller;
    if (controller == null || controller.value.isRecordingVideo) return;

    setState(() {
      _phase = _Phase.recording;
      _elapsed = Duration.zero;
      _lastSaved = null;
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed += const Duration(seconds: 1));
    });

    try {
      await controller.startVideoRecording();
    } on CameraException catch (e) {
      _ticker?.cancel();
      setState(() => _phase = _Phase.idle);
      _notify(_describe(e));
    }
  }

  Future<void> _stop() async {
    final controller = _controller;
    if (controller == null) return;

    _ticker?.cancel();
    setState(() => _phase = _Phase.idle);

    try {
      final recording = await controller.stopVideoRecording();
      final saved = await _store.save(recording);
      if (!mounted) return;
      setState(() {
        _lastSaved = saved;
      });
      _notify('Saved ${saved.fileName}');
    } on CameraException catch (e) {
      _notify(_describe(e));
    } on FileSystemException catch (e) {
      _notify('Could not save the recording: ${e.message}');
    } on PlatformException catch (e) {
      _notify('Could not reach the chosen folder: ${e.message ?? e.code}');
    }
  }

  void _fail(String message, {bool blocked = false}) {
    if (!mounted) return;
    setState(() {
      _error = message;
      _permissionBlocked = blocked;
      _phase = _Phase.error;
    });
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _describe(CameraException e) => switch (e.code) {
    'CameraAccessDenied' => 'Camera permission was denied.',
    'CameraAccessDeniedWithoutPrompt' =>
      'Camera permission is blocked for Dash Cam.',
    'CameraAccessRestricted' => 'Camera access is restricted on this device.',
    _ => 'Camera error ${e.code}: ${e.description ?? 'unknown'}',
  };

  @override
  Widget build(BuildContext context) {
    // Plan item 5: the preview is the full-bleed background and the controls
    // float over it, so the controls can never squeeze the preview or move
    // under the user's finger. The Builder puts a context *below* this
    // Scaffold, which is what openDrawer needs to find it.
    return Scaffold(
      backgroundColor: Colors.black,
      drawer: const DashCamDrawer(current: DashCamPage.capture),
      body: Builder(
        builder: (context) => Stack(
          fit: StackFit.expand,
          children: [
            _buildPreview(),
            _buildTopOverlay(context),
            _buildBottomOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return _buildUnavailable();
    }
    // CameraPreview re-frames itself from the device orientation, which changes
    // without this widget rebuilding, so follow the controller's notifications.
    return ValueListenableBuilder<CameraValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final size = _previewSize(value);
        return LayoutBuilder(
          builder: (context, constraints) {
            return ClipRect(
              child: FittedBox(
                fit: _previewFit(constraints.biggest, size),
                child: SizedBox(
                  width: size.width,
                  height: size.height,
                  child: CameraPreview(controller),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// The sizes the plugin reports are always in the sensor's landscape
  /// orientation, while [CameraPreview] rotates and re-frames the texture
  /// itself from the *device* orientation. Those only agree when the window
  /// follows the device, so the box handed to the preview has to be derived
  /// from the same orientation the preview uses internally — otherwise the
  /// texture is stretched to fit a box of the wrong shape and BoxFit.cover
  /// then crops away most of the frame.
  Size _previewSize(CameraValue value) {
    final orientation = value.isRecordingVideo
        ? (value.recordingOrientation ?? value.deviceOrientation)
        : (value.lockedCaptureOrientation ?? value.deviceOrientation);
    final landscape =
        orientation == DeviceOrientation.landscapeLeft ||
        orientation == DeviceOrientation.landscapeRight;
    final size = value.previewSize;
    if (size == null) {
      final ratio = value.aspectRatio;
      return landscape ? Size(1, ratio) : Size(ratio, 1);
    }
    return landscape ? size : Size(size.height, size.width);
  }

  /// Picks the fit from the geometry instead of from the orientation, because
  /// the geometry is what actually decides which axis a cover would crop.
  ///
  /// [frame] is already re-oriented by [_previewSize], so in portrait the frame
  /// is relatively taller than the full-bleed box and `cover` would scale to the
  /// height and throw away horizontal field of view. On a dash cam the sides of
  /// the frame are what matter — adjacent lanes, oncoming traffic — so portrait
  /// letterboxes with `contain` instead and shows the whole frame. In landscape
  /// the box is relatively wider, the cover crop is only vertical, and filling the
  /// screen is the better trade.
  BoxFit _previewFit(Size box, Size frame) {
    if (!box.width.isFinite ||
        !box.height.isFinite ||
        box.width <= 0 ||
        box.height <= 0 ||
        frame.width <= 0 ||
        frame.height <= 0) {
      return BoxFit.contain;
    }
    return box.width / box.height < frame.width / frame.height
        ? BoxFit.contain
        : BoxFit.cover;
  }

  Widget _buildUnavailable() {
    if (_phase == _Phase.error) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_off, color: Colors.white70, size: 48),
              const SizedBox(height: 16),
              Text(
                _error ?? 'The camera is unavailable.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _permissionBlocked ? openAppSettings : _openCamera,
                child: Text(_permissionBlocked ? 'Open settings' : 'Retry'),
              ),
            ],
          ),
        ),
      );
    }
    return const Center(child: CircularProgressIndicator());
  }

  /// Scrim-backed top strip: just the menu and the title, floating over the
  /// preview instead of reserving an app bar's worth of height.
  Widget _buildTopOverlay(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xB3000000), Color(0x00000000)],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: 48,
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Scaffold.of(context).openDrawer(),
                  icon: const Icon(Icons.menu),
                  color: Colors.white,
                  tooltip: 'Open navigation menu',
                ),
                const Text(
                  'Dash Cam',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomOverlay() {
    final recording = _phase == _Phase.recording;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Color(0xB3000000), Color(0x00000000)],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 28, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildStatus(),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildCircleButton(
                      tooltip: 'Start recording',
                      icon: Icons.fiber_manual_record,
                      background: Colors.redAccent,
                      foreground: Colors.white,
                      onPressed: recording || _controller == null
                          ? null
                          : _start,
                    ),
                    const SizedBox(width: 24),
                    _buildCircleButton(
                      tooltip: 'Stop recording',
                      icon: Icons.stop_rounded,
                      background: Colors.white,
                      foreground: Colors.black,
                      onPressed: recording ? _stop : null,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildSavedLabel(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Icon-only is the camera-app convention, and the record-dot / stop-square
  /// glyphs are universal. Note the tap target stays at 56x56: dropping the
  /// text label saves width, not height, so the height that comes back is from
  /// overlaying the controls rather than from shrinking the buttons.
  Widget _buildCircleButton({
    required String tooltip,
    required IconData icon,
    required Color background,
    required Color foreground,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: 56,
      height: 56,
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(icon, size: 26),
        style: IconButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          disabledBackgroundColor: Colors.white24,
          disabledForegroundColor: Colors.white38,
          shape: const CircleBorder(),
        ),
      ),
    );
  }

  /// Fixed-height slot. The old layout appended this row to the controls
  /// column only when a file existed, which reflowed the Start/Stop buttons
  /// above it by 88px. Reserving the height unconditionally is what keeps
  /// those buttons at a fixed position across idle -> recording -> saved.
  Widget _buildSavedLabel() {
    final saved = _lastSaved;
    return SizedBox(
      height: 16,
      child: Text(
        saved == null ? '' : '${saved.fileName} · ${saved.where}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white54, fontSize: 12),
      ),
    );
  }

  Widget _buildStatus() {
    final label = switch (_phase) {
      _Phase.starting => 'Starting camera…',
      _Phase.idle => 'Ready',
      _Phase.recording => 'Recording ${_format(_elapsed)}',
      _Phase.error => 'Camera unavailable',
    };
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (_phase == _Phase.recording) ...[
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: Colors.redAccent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      ],
    );
  }

  static String _format(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
