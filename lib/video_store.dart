import 'dart:io';

import 'package:camera/camera.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'storage_location.dart';

/// Where a finished recording ended up, for showing to the user.
class SavedRecording {
  const SavedRecording({required this.fileName, required this.where});

  final String fileName;

  /// A file path for app-private storage, a folder name for a chosen folder.
  final String where;
}

/// Owns where finished recordings end up on disk.
///
/// The `camera` plugin gives no way to choose an output path, so it always
/// writes into the app's private cache directory. Every finished recording is
/// relocated from here, so changing the storage location is a change to this
/// file and [StorageLocationStore] alone and never reaches the capture UI.
class VideoStore {
  VideoStore(this._locations);

  final StorageLocationStore _locations;

  Future<SavedRecording> save(XFile recording) async {
    final fileName = 'dashcam_${_stamp(DateTime.now())}.mp4';
    final source = File(recording.path);
    final location = await _locations.load();

    if (location == null) return _saveToAppFolder(source, fileName);

    // A content:// tree cannot be written from dart, so hand the file over.
    await _locations.copyInto(
      treeUri: location.treeUri,
      sourcePath: source.path,
      fileName: fileName,
    );
    await _deleteQuietly(source);
    return SavedRecording(fileName: fileName, where: location.label);
  }

  Future<SavedRecording> _saveToAppFolder(File source, String fileName) async {
    final directory = await getApplicationDocumentsDirectory();
    final destination = File(p.join(directory.path, fileName));
    try {
      // Cache and documents live on the same filesystem, so this is a
      // metadata-only move rather than a copy of the whole video.
      await source.rename(destination.path);
    } on FileSystemException {
      // Different filesystems cannot rename; fall back to a full copy.
      await source.copy(destination.path);
      await _deleteQuietly(source);
    }
    return SavedRecording(fileName: fileName, where: destination.path);
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (file.existsSync()) await file.delete();
    } on FileSystemException {
      // Leaving the temporary copy behind is not worth failing the recording.
    }
  }

  static String _stamp(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}${two(time.month)}${two(time.day)}'
        '_${two(time.hour)}${two(time.minute)}${two(time.second)}';
  }
}
