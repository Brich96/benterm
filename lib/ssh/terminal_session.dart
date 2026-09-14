import 'dart:async';

/// A bidirectional byte stream that can back a terminal.
///
/// The terminal layer only ever talks to this interface, so the same
/// [TerminalPane] renders a local stub session today and a real SSH session
/// once `dartssh2` is wired up.
abstract class TerminalSession {
  /// Data produced by the remote end, to be fed into the terminal.
  Stream<String> get output;

  /// Completes when the session ends, normally or otherwise.
  Future<void> get done;

  /// Opens the session. Throws if it cannot be established.
  Future<void> start();

  /// Sends user input (keystrokes, pasted text) to the remote end.
  void write(String data);

  /// Notifies the remote end that the terminal geometry changed.
  void resize(int width, int height, int pixelWidth, int pixelHeight);

  /// Tears the session down.
  Future<void> close();
}
