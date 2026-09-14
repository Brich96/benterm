import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import 'package:benterm/ssh/terminal_session.dart';

/// Renders a [TerminalSession] as an interactive terminal.
///
/// Owns the wiring in both directions: session output is written into the
/// [Terminal] buffer, and the terminal's keystrokes and resizes are pushed
/// back out to the session.
class TerminalPane extends StatefulWidget {
  const TerminalPane({super.key, required this.session});

  final TerminalSession session;

  @override
  State<TerminalPane> createState() => _TerminalPaneState();
}

class _TerminalPaneState extends State<TerminalPane> {
  final _terminal = Terminal(maxLines: 10000);
  final _controller = TerminalController();

  /// Output that arrived before the terminal had been laid out. Writing into
  /// [Terminal] before first layout trips a `hasSize` assertion inside
  /// xterm's render object, so early bytes wait here.
  final _pending = StringBuffer();

  StreamSubscription<String>? _subscription;
  var _laidOut = false;

  @override
  void initState() {
    super.initState();

    _terminal.onOutput = widget.session.write;
    _terminal.onResize = widget.session.resize;
    _subscription = widget.session.output.listen(_receive);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _laidOut = true;
      if (_pending.isNotEmpty) {
        _terminal.write(_pending.toString());
        _pending.clear();
      }
      unawaited(_open());
    });
  }

  Future<void> _open() async {
    try {
      await widget.session.start();
    } catch (error) {
      _receive('\r\n\x1b[31msession failed: $error\x1b[0m\r\n');
    }
  }

  void _receive(String data) {
    if (_laidOut) {
      _terminal.write(data);
    } else {
      _pending.write(data);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    unawaited(widget.session.close());
    _controller.dispose();
    super.dispose();
  }

  /// On desktop the OS always gives us a hardware keyboard, and xterm's
  /// IME/text-input path does not deliver insertions there — so printable
  /// characters are handled in [_handlePrintableKey] instead. Mobile keeps
  /// the text-input path, which the on-screen keyboard and IMEs require.
  static bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  /// Sends printable characters straight to the session.
  ///
  /// Returns [KeyEventResult.ignored] for anything with a modifier or any
  /// control character, leaving Ctrl-C, Enter, Tab, backspace and the arrow
  /// keys to xterm's own keytab handling.
  KeyEventResult _handlePrintableKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;

    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      return KeyEventResult.ignored;
    }

    final character = event.character;
    if (character == null || character.isEmpty) return KeyEventResult.ignored;

    final code = character.codeUnitAt(0);
    if (code < 0x20 || code == 0x7f) return KeyEventResult.ignored;

    _terminal.textInput(character);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return TerminalView(
      _terminal,
      controller: _controller,
      autofocus: true,
      theme: TerminalThemes.defaultTheme,
      textStyle: const TerminalStyle(fontSize: 14),
      padding: const EdgeInsets.all(8),
      hardwareKeyboardOnly: _isDesktop,
      onKeyEvent: _isDesktop ? _handlePrintableKey : null,
    );
  }
}
