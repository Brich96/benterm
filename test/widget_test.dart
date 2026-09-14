import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

import 'package:benterm/ssh/echo_session.dart';
import 'package:benterm/ssh/ssh_host.dart';
import 'package:benterm/terminal/terminal_pane.dart';
import 'package:benterm/ui/app.dart';
import 'package:benterm/vault/secret_store.dart';
import 'package:benterm/vault/vault_blob_store.dart';

/// Pumps until [finder] matches.
///
/// Argon2id derivation runs on an isolate, which fake test time cannot
/// advance, so each attempt hands back real wall time via [runAsync] before
/// pumping the next frame.
Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  int maxAttempts = 60,
}) async {
  for (var i = 0; i < maxAttempts; i++) {
    await tester.pump();
    if (finder.evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
  }
  fail('timed out waiting for ${finder.describeMatch(Plurality.one)}');
}

String readTerminal(WidgetTester tester) {
  final view = tester.widget<TerminalView>(find.byType(TerminalView));
  final terminal = view.terminal;
  return [
    for (var i = 0; i < terminal.viewHeight; i++)
      terminal.buffer.lines[i].toString(),
  ].join('\n');
}

void main() {
  Widget app() => BentermApp(
    blobStore: MemoryVaultBlobStore(),
    secretStore: MemorySecretStore(),
  );

  Future<void> createVault(WidgetTester tester) async {
    await tester.pumpWidget(app());
    await pumpUntil(tester, find.text('Create a new vault'));
    await tester.tap(find.widgetWithText(FilledButton, 'Create a new vault'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Passphrase'),
      'correct horse battery staple',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirm passphrase'),
      'correct horse battery staple',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create vault'));
    await pumpUntil(tester, find.text('No hosts yet'));
  }

  testWidgets('first run offers both a new vault and an existing one', (
    tester,
  ) async {
    // A fresh device cannot tell whether a vault already exists on GitHub:
    // the repo and token live in this device's keychain, which is empty.
    // So the choice has to be offered rather than assumed.
    await tester.pumpWidget(app());
    await pumpUntil(tester, find.text('Create a new vault'));

    expect(find.widgetWithText(FilledButton, 'Create a new vault'),
        findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Use my existing vault'),
        findsOneWidget);
  });

  testWidgets('joining an existing vault asks for the repo first', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await pumpUntil(tester, find.text('Use my existing vault'));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Use my existing vault'));
    await tester.pumpAndSettle();

    expect(find.text('GitHub sync'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Repository'), findsOneWidget);
  });

  testWidgets('a mistyped confirmation blocks vault creation', (tester) async {
    await tester.pumpWidget(app());
    await pumpUntil(tester, find.text('Create a new vault'));
    await tester.tap(find.widgetWithText(FilledButton, 'Create a new vault'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Passphrase'),
      'correct horse battery staple',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirm passphrase'),
      'something else',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create vault'));
    await tester.pump();

    expect(find.text('Passphrases do not match'), findsOneWidget);
    expect(find.text('No hosts yet'), findsNothing);
  });

  testWidgets('creating a vault opens an empty host list', (tester) async {
    await createVault(tester);

    expect(find.text('Hosts'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Add a host'), findsOneWidget);
  });

  testWidgets('an added host appears in the list', (tester) async {
    await createVault(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Add a host'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Host'),
      'example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Username'),
      'ben',
    );
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await pumpUntil(tester, find.text('ben@example.com'));

    expect(find.text('ben@example.com'), findsOneWidget);
    expect(find.text('ben@example.com:22'), findsOneWidget);
  });

  testWidgets('output arriving before first layout is not dropped', (
    tester,
  ) async {
    // Regression: writing into the terminal before its render object has
    // been laid out trips a `hasSize` assertion, which only reproduced in
    // the real app because the microtask beat the first frame.
    final session = EchoSession();
    await tester.pumpWidget(MaterialApp(home: TerminalPane(session: session)));
    session.write('hi\r');
    await tester.pump();
    await tester.pump();

    expect(readTerminal(tester), contains('you typed: hi'));
    expect(tester.takeException(), isNull);
  });

  test('echo session echoes input and handles backspace', () async {
    final session = EchoSession();
    final seen = StringBuffer();
    session.output.listen(seen.write);

    await session.start();
    session.write('ab');
    session.write('\x7f');
    session.write('\r');
    await Future<void>.delayed(Duration.zero);

    expect(seen.toString(), contains('\b \b'));
    expect(seen.toString(), contains('you typed: a'));

    await session.close();
  });

  test('host display name falls back to user@host', () {
    const host = SshHost(hostname: 'example.com', username: 'ben');
    expect(host.displayName, 'ben@example.com');
    expect(host.port, 22);
  });
}
