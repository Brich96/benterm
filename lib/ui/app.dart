import 'package:flutter/material.dart';

import 'package:benterm/vault/github_vault_store.dart';
import 'package:benterm/vault/secret_store.dart';
import 'package:benterm/vault/vault_blob_store.dart';
import 'package:benterm/vault/vault_service.dart';
import 'package:benterm/ui/unlock_screen.dart';
import 'package:benterm/ui/welcome_screen.dart';

class BentermApp extends StatefulWidget {
  const BentermApp({super.key, this.blobStore, this.secretStore});

  /// Overridable for tests; defaults to the platform locations.
  final VaultBlobStore? blobStore;
  final SecretStore? secretStore;

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
                )
              : WelcomeScreen(service: _service, settings: settings);
        },
      ),
    );
  }
}
