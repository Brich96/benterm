import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

import 'package:benterm/ssh/terminal_session.dart';
import 'package:benterm/terminal/key_toolbar.dart';
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

  testWidgets('desktop shows no on-screen key toolbar', (tester) async {
    await pumpPane(tester);
    final toolbars = find.byType(KeyToolbar).evaluate().length;
    debugDefaultTargetPlatformOverride = null;

    expect(toolbars, 0);
  });

  group('mobile', () {
    Future<void> pumpMobilePane(WidgetTester tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: TerminalPane(session: session))),
      );
      await tester.pump();
      await tester.pump();
    }

    Terminal terminalOf(WidgetTester tester) =>
        tester.widget<TerminalView>(find.byType(TerminalView)).terminal;

    testWidgets('the key toolbar is shown', (tester) async {
      await pumpMobilePane(tester);
      final toolbars = find.byType(KeyToolbar).evaluate().length;
      debugDefaultTargetPlatformOverride = null;

      expect(toolbars, 1);
    });

    testWidgets('esc sends an escape', (tester) async {
      await pumpMobilePane(tester);
      await tester.tap(find.text('esc'));
      await tester.pump();

      expect(sentAfterKeys(), '\x1b');
    });

    testWidgets('arrows send cursor sequences', (tester) async {
      await pumpMobilePane(tester);
      await tester.tap(find.byIcon(Icons.arrow_upward));
      await tester.pump();

      expect(sentAfterKeys(), '\x1b[A');
    });

    testWidgets('sticky ctrl turns the next letter into a control code', (
      tester,
    ) async {
      await pumpMobilePane(tester);
      await tester.tap(find.text('ctrl'));
      await tester.pump();

      // Mobile keeps xterm's text-input path, so simulate what it delivers.
      terminalOf(tester).textInput('c');
      await tester.pump();

      expect(sentAfterKeys(), '\x03');
    });

    testWidgets('ctrl applies once and then clears', (tester) async {
      await pumpMobilePane(tester);
      await tester.tap(find.text('ctrl'));
      await tester.pump();

      final terminal = terminalOf(tester);
      terminal.textInput('c');
      await tester.pump();
      terminal.textInput('c');
      await tester.pump();

      expect(sentAfterKeys(), '\x03c');
    });
  });
}
