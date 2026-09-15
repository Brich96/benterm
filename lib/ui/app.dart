import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';

import 'package:benterm/update/update_service.dart';
import 'package:benterm/vault/github_vault_store.dart';
import 'package:benterm/vault/secret_store.dart';
import 'package:benterm/vault/vault_blob_store.dart';
import 'package:benterm/vault/vault_service.dart';
import 'package:benterm/ui/unlock_screen.dart';
import 'package:benterm/ui/welcome_screen.dart';

class BentermApp extends StatefulWidget {
  const BentermApp({super.key, this.blobStore, this.secretStore, this.updates});

  /// Overridable for tests; defaults to the platform locations.
  final VaultBlobStore? blobStore;
  final SecretStore? secretStore;

  /// Overridable for tests, which must not reach out to GitHub.
  final UpdateService? updates;

  @override
  State<BentermApp> createState() => _BentermAppState();
}

class _BentermAppState extends State<BentermApp> {
  late final VaultBlobStore _blobStore =
      widget.blobStore ?? FileVaultBlobStore();
  late final SecretStore _secretStore =
      widget.secretStore ?? const PlatformSecretStore();

  late final VaultService _service = VaultService(
    blobStore: _blobStore,
    remote: GithubVaultStore(),
  );

  late final UpdateService _updates = widget.updates ?? UpdateService();

  /// Runs a staged update once the app is closing, when the user asked for
  /// it to be installed on exit. The helper waits for this process to go
  /// away before replacing anything.
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onExitRequested: () async {
      if (_updates.installOnExit && _updates.hasStagedUpdate) {
        await _updates.applyOnExit();
      }
      return AppExitResponse.exit;
    },
  );

  @override
  void initState() {
    super.initState();
    _lifecycle;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _updates.close();
    super.dispose();
  }

  late final Future<bool> _hasVault = _blobStore.readBlob().then(
    (blob) => blob != null,
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'benterm',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4C8BF5),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: FutureBuilder<bool>(
        future: _hasVault,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          final settings = VaultSyncSettings(_secretStore);

          // With a vault on this device, go straight to the passphrase.
          // Without one, the device might still be joining an existing
          // vault on GitHub, which only the user can tell us.
          return snapshot.data!
              ? UnlockScreen(
                  service: _service,
                  settings: settings,
                  mode: VaultEntryMode.unlock,
                  updates: _updates,
                )
              : WelcomeScreen(
                  service: _service,
                  settings: settings,
                  updates: _updates,
                );
        },
      ),
    );
  }
}
