import 'package:flutter/material.dart';

import 'capture_screen.dart';
import 'settings_screen.dart';

enum DashCamPage { capture, settings }

/// Menu shared by both screens, so either one can reach the other.
class DashCamDrawer extends StatelessWidget {
  const DashCamDrawer({super.key, required this.current});

  final DashCamPage current;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: Colors.deepPurple),
            child: Center(
              child: Text(
                'Dash Cam',
                style: TextStyle(color: Colors.white, fontSize: 22),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.videocam_outlined),
            title: const Text('Capture'),
            selected: current == DashCamPage.capture,
            onTap: () => _goTo(context, DashCamPage.capture),
          ),
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Settings'),
            selected: current == DashCamPage.settings,
            onTap: () => _goTo(context, DashCamPage.settings),
          ),
        ],
      ),
    );
  }

  void _goTo(BuildContext context, DashCamPage page) {
    final navigator = Navigator.of(context);
    navigator.pop();
    if (page == current) return;
    navigator.pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => switch (page) {
          DashCamPage.capture => const CaptureScreen(),
          DashCamPage.settings => const SettingsScreen(),
        },
      ),
    );
  }
}

/// The app bar both screens share, so the menu is always in the same place.
/// Pair it with [DashCamDrawer] on the enclosing `Scaffold`.
class DashCamAppBar extends StatelessWidget implements PreferredSizeWidget {
  const DashCamAppBar({super.key, required this.title, required this.page});

  final String title;
  final DashCamPage page;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(title),
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      iconTheme: const IconThemeData(color: Colors.white),
    );
  }
}
