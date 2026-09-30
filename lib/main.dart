import 'package:flutter/material.dart';

import 'capture_screen.dart';

void main() {
  runApp(const DashCamApp());
}

class DashCamApp extends StatelessWidget {
  const DashCamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dash Cam',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: .fromSeed(seedColor: Colors.deepPurple)),
      home: const CaptureScreen(),
    );
  }
}
