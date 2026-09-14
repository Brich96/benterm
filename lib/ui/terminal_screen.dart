import 'package:flutter/material.dart';

import 'package:benterm/ssh/terminal_session.dart';
import 'package:benterm/terminal/terminal_pane.dart';

/// Single full-window terminal for one session. Multi-session tabs and the
/// host list arrive with the vault work; this is the one-session case they
/// will wrap.
class TerminalScreen extends StatelessWidget {
  const TerminalScreen({
    super.key,
    required this.session,
    required this.title,
  });

  final TerminalSession session;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        titleTextStyle: Theme.of(context).textTheme.titleMedium,
        toolbarHeight: 40,
      ),
      body: TerminalPane(session: session),
    );
  }
}
