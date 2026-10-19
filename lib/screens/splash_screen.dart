import 'package:flutter/material.dart';

import 'root_decider.dart';

/// Maintains the existing app entry point without adding an artificial delay.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) => const RootDecider();
}
