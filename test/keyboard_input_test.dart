import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:benterm/ssh/terminal_session.dart';
import 'package:benterm/terminal/terminal_pane.dart';

/// Records what the terminal sends, without any transport behind it.
class _RecordingSession implements TerminalSession {
  final sent = StringBuffer();
  final _output = StreamController<String>.broadcast();
  final _done = Completer<void>();

  @override
  Stream<String> get output => _output.stream;

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> start() async {}

  @override
  void write(String data) => sent.write(data);

  @override
  void resize(int width, int height, int pixelWidth, int pixelHeight) {}

  @override
  Future<void> close() async {
    if (!_done.isCompleted) _done.complete();
    await _output.close();
  }
}

void main() {
  late _RecordingSession session;

  setUp(() => session = _RecordingSession());

  // The framework asserts the platform override is unset by the time the
  // test body returns, so it is cleared by [sentAfterKeys] rather than in
  // tearDown.
  Future<void> pumpPane(WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await tester.pumpWidget(MaterialApp(home: TerminalPane(session: session)));
    await tester.pump();
    await tester.pump();
  }

  String sentAfterKeys() {
    debugDefaultTargetPlatformOverride = null;
    return session.sent.toString();
  }

  testWidgets('printable characters reach the session on desktop', (
    tester,
  ) async {
    // Regression: on Windows only Enter made it through, because printable
    // characters went through xterm's IME/text-input path.
    await pumpPane(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyH, character: 'h');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI, character: 'i');

    expect(sentAfterKeys(), 'hi');
  });

  testWidgets('enter still sends a carriage return', (tester) async {
    await pumpPane(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);

    expect(sentAfterKeys(), '\r');
  });

  testWidgets('ctrl-c is not swallowed as a printable character', (
    tester,
  ) async {
    await pumpPane(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC, character: 'c');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    expect(sentAfterKeys(), '\x03');
  });

  testWidgets('backspace sends a delete, not a literal character', (
    tester,
  ) async {
    await pumpPane(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);

    expect(sentAfterKeys(), '\x7f');
  });
}
