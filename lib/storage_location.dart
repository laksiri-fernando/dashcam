import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A folder the user granted Dash Cam access to through Android's Storage
/// Access Framework.
class StorageLocation {
  const StorageLocation({required this.treeUri, required this.label});

  final String treeUri;

  /// Human readable name of the picked folder, e.g. `Downloads`.
  final String label;

  @override
  bool operator ==(Object other) =>
      other is StorageLocation && other.treeUri == treeUri;

  @override
  int get hashCode => treeUri.hashCode;
}

/// Reads and writes the configured recording destination.
///
/// The picked folder is a `content://` tree URI, which `dart:io` cannot open,
/// so the actual copy is delegated to [MainActivity] over a method channel.
class StorageLocationStore {
  static const _channel = MethodChannel('dashcam/storage');
  static const _prefsKey = 'dashcam.storage.tree_uri';

  /// The configured folder, or `null` while the user has not chosen one.
  Future<StorageLocation?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final treeUri = prefs.getString(_prefsKey);
    if (treeUri == null) return null;
    return StorageLocation(treeUri: treeUri, label: await _labelOf(treeUri));
  }

  /// Opens the system folder picker. Returns `null` if the user backed out.
  Future<StorageLocation?> choose() async {
    final treeUri = await _channel.invokeMethod<String>('chooseFolder');
    if (treeUri == null) return null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, treeUri);
    return StorageLocation(treeUri: treeUri, label: await _labelOf(treeUri));
  }

  /// Forgets the chosen folder, sending recordings back to app storage.
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  /// Copies [sourcePath] into the granted folder. Returns the new document URI.
  Future<String> copyInto({
    required String treeUri,
    required String sourcePath,
    required String fileName,
  }) async {
    final uri = await _channel.invokeMethod<String>('copyInto', {
      'treeUri': treeUri,
      'sourcePath': sourcePath,
      'fileName': fileName,
    });
    if (uri == null) {
      throw const FileSystemException(
        'The chosen folder did not return a location',
      );
    }
    return uri;
  }

  Future<String> _labelOf(String treeUri) async {
    try {
      final label = await _channel.invokeMethod<String>('folderLabel', {
        'treeUri': treeUri,
      });
      return label ?? 'Selected folder';
    } on PlatformException {
      // A stale or revoked grant still needs a usable label.
      return 'Selected folder';
    }
  }
}
