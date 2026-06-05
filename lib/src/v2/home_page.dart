import 'package:flutter/material.dart';

import '../app/authenticated_app_context.dart';
import 'home_shell.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.app});

  final AuthenticatedAppContext app;

  @override
  Widget build(BuildContext context) {
    return HomeShell(app: app);
  }
}
