import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

import 'package:benterm/ssh/echo_session.dart';
import 'package:benterm/ssh/ssh_host.dart';
import 'package:benterm/ui/host_list_screen.dart';
import 'package:benterm/ui/sessions_screen.dart';
import 'package:benterm/vault/secret_store.dart';
import 'package:benterm/vault/vault_blob_store.dart';
import 'package:benterm/vault/vault_service.dart';

/// Builds an unlocked vault holding [hosts].
///
/// Runs through [WidgetTester.runAsync] because Argon2id derives the key on
/// an isolate, which fake test time cannot advance: awaiting it directly
/// inside testWidgets never returns.
Future<VaultService> unlockedVault(
  WidgetTester tester,
  List<SshHost> hosts,
) async {
  final service = await tester.runAsync(() async {
    final service = VaultService(blobStore: MemoryVaultBlobStore());
    await service.unlock('a test passphrase');
    for (final host in hosts) {
      await service.upsertHost(host);
    }
    return service;
  });
  return service!;
}

SshHost host(String name, {int port = 22}) =>
    SshHost.create(hostname: '$name.example', username: 'ben', port: port);

/// [WidgetTester.pumpAndSettle] never returns with a terminal on screen:
/// the blinking cursor is an animation that never finishes.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('a session opens as a single pane with no tab strip', (
    tester,
  ) async {
    final service = await unlockedVault(tester, []);
    final target = host('one');

    await tester.pumpWidget(
      MaterialApp(
        home: SessionsScreen(
          host: target,
          service: service,
          sessionBuilder: (_) => EchoSession(),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(TerminalView), findsOneWidget);
    expect(find.text(target.displayName), findsOneWidget);
    // The close control is the plain one, not a per-tab chip.
    expect(find.byTooltip('Close session'), findsOneWidget);
  });

  testWidgets('opening a second session keeps the first one alive', (
    tester,
  ) async {
    final first = host('one');
    final second = host('two');
    final service = await unlockedVault(tester, [first, second]);

    await tester.pumpWidget(
      MaterialApp(
        home: SessionsScreen(
          host: first,
          service: service,
          sessionBuilder: (_) => EchoSession(),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Open another session'));
    await settle(tester);
    await tester.tap(find.text(second.displayName).last);
    await settle(tester);

    // Both panes stay mounted: a background session must not be torn down,
    // which would drop its connection and scrollback.
    expect(find.byType(TerminalView, skipOffstage: false), findsNWidgets(2));
    expect(find.byType(IndexedStack), findsOneWidget);
  });

  testWidgets('closing the only session leaves the screen', (tester) async {
    final service = await unlockedVault(tester, []);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SessionsScreen(
                    host: host('one'),
                    service: service,
                    sessionBuilder: (_) => EchoSession(),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await settle(tester);
    expect(find.byType(TerminalView), findsOneWidget);

    await tester.tap(find.byTooltip('Close session'));
    await settle(tester);

    expect(find.byType(TerminalView), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  group('host search', () {
    Future<void> pumpList(WidgetTester tester, VaultService service) async {
      await tester.pumpWidget(
        MaterialApp(
          home: HostListScreen(
            service: service,
            settings: VaultSyncSettings(MemorySecretStore()),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('is hidden until the list is long enough to need it', (
      tester,
    ) async {
      await pumpList(
        tester,
        await unlockedVault(tester, [host('one'), host('two')]),
      );

      expect(find.widgetWithText(TextField, 'Search hosts'), findsNothing);
    });

    testWidgets('filters by hostname', (tester) async {
      final service = await unlockedVault(tester, [
        for (final name in [
          'alpha',
          'beta',
          'gamma',
          'delta',
          'epsilon',
          'zeta',
        ])
          host(name),
      ]);
      await pumpList(tester, service);

      expect(find.byType(ListTile), findsNWidgets(6));

      await tester.enterText(find.byType(TextField), 'gam');
      await tester.pump();

      expect(find.text('ben@gamma.example'), findsOneWidget);
      expect(find.text('ben@alpha.example'), findsNothing);
    });

    testWidgets('says so when nothing matches', (tester) async {
      final service = await unlockedVault(tester, [
        for (final name in [
          'alpha',
          'beta',
          'gamma',
          'delta',
          'epsilon',
          'zeta',
        ])
          host(name),
      ]);
      await pumpList(tester, service);

      await tester.enterText(find.byType(TextField), 'nothing-like-this');
      await tester.pump();

      expect(find.text('No hosts match that search'), findsOneWidget);
    });

    testWidgets('matches on the label too', (tester) async {
      final service = await unlockedVault(tester, [
        SshHost.create(
          hostname: 'a1b2c3.example',
          username: 'ben',
          label: 'production web',
        ),
        for (final name in ['beta', 'gamma', 'delta', 'epsilon', 'zeta'])
          host(name),
      ]);
      await pumpList(tester, service);

      await tester.enterText(find.byType(TextField), 'production');
      await tester.pump();

      expect(find.text('production web'), findsOneWidget);
      expect(find.byType(ListTile), findsOneWidget);
    });
  });
}
