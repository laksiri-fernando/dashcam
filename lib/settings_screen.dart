import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_drawer.dart';
import 'storage_location.dart';

/// Plan item 2: choose where recordings are written.
///
/// A chosen folder is granted through Android's Storage Access Framework, so
/// the files land somewhere the user can reach with a file manager or gallery.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final StorageLocationStore _locations = StorageLocationStore();

  StorageLocation? _location;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final location = await _locations.load();
    if (!mounted) return;
    setState(() {
      _location = location;
      _loading = false;
    });
  }

  Future<void> _chooseFolder() async {
    try {
      final chosen = await _locations.choose();
      if (!mounted) return;
      setState(() => _location = chosen);
      _notify(
        chosen == null
            ? 'Folder unchanged.'
            : 'Recordings will be saved to ${chosen.label}.',
      );
    } on PlatformException catch (e) {
      _notify('Could not open the folder chooser: ${e.message ?? e.code}');
    }
  }

  Future<void> _useAppFolder() async {
    await _locations.clear();
    if (!mounted) return;
    setState(() => _location = null);
    _notify('Recordings will be saved in the app folder.');
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final location = _location;

    return Scaffold(
      appBar: const DashCamAppBar(
        title: 'Settings',
        page: DashCamPage.settings,
      ),
      drawer: const DashCamDrawer(current: DashCamPage.settings),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                Text(
                  'Recording location',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    leading: Icon(
                      location == null
                          ? Icons.lock_outline
                          : Icons.folder_outlined,
                    ),
                    title: Text(
                      location == null ? 'App folder' : location.label,
                    ),
                    subtitle: Text(
                      location == null
                          ? 'Only Dash Cam can read these files.'
                          : 'Recordings are saved in this folder.',
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _chooseFolder,
                  icon: const Icon(Icons.drive_folder_upload_outlined),
                  label: Text(
                    location == null ? 'Choose folder' : 'Change folder',
                  ),
                ),
                if (location != null) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _useAppFolder,
                    icon: const Icon(Icons.undo),
                    label: const Text('Use app folder instead'),
                  ),
                ],
                const SizedBox(height: 24),
                const Text(
                  'Choosing a folder opens the Android file picker and grants '
                  'Dash Cam access to that folder only. Pick somewhere such as '
                  'Downloads if you want to watch recordings on the phone.',
                ),
              ],
            ),
    );
  }
}
