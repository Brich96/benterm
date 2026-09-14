import 'dart:async';

import 'package:benterm/ssh/terminal_session.dart';

/// A [TerminalSession] with no network behind it.
///
/// Stands in for a real connection while the terminal layer is being built:
/// it echoes keystrokes, honours backspace, and prints a prompt on Enter, so
/// the full input/output path can be exercised before SSH exists.
class EchoSession implements TerminalSession {
  final _output = StreamController<String>.broadcast();
  final _done = Completer<void>();

  static const _prompt = 'benterm\$ ';

  var _line = '';

  @override
  Stream<String> get output => _output.stream;

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> start() async {
    _emit('benterm — local echo session (no SSH yet)\r\n');
    _emit('Type something; Enter echoes the line back.\r\n\r\n');
    _emit(_prompt);
  }

  @override
  void write(String data) {
    for (final rune in data.runes) {
      switch (rune) {
        case 0x0d: // Enter
          _emit('\r\n');
          if (_line.isNotEmpty) _emit('you typed: $_line\r\n');
          _line = '';
          _emit(_prompt);
        case 0x7f: // Backspace
        case 0x08:
          if (_line.isNotEmpty) {
            _line = _line.substring(0, _line.length - 1);
            _emit('\b \b');
          }
        case 0x03: // Ctrl-C
          _line = '';
          _emit('^C\r\n$_prompt');
        default:
          if (rune >= 0x20) {
            final char = String.fromCharCode(rune);
            _line += char;
            _emit(char);
          }
      }
    }
  }

  @override
  void resize(int width, int height, int pixelWidth, int pixelHeight) {
    // Nothing to tell: the echo session has no remote pty.
  }

  @override
  Future<void> close() async {
    if (!_done.isCompleted) _done.complete();
    await _output.close();
  }

  void _emit(String data) {
    if (!_output.isClosed) _output.add(data);
  }
}
