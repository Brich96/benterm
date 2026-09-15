import 'package:flutter/material.dart';

import 'package:benterm/vault/github_vault_store.dart';
import 'package:benterm/vault/secret_store.dart';
import 'package:benterm/update/update_service.dart';
import 'package:benterm/vault/vault_service.dart';
import 'package:benterm/ui/sync_settings_screen.dart';
import 'package:benterm/ui/unlock_screen.dart';

/// First run on a device with no vault: start a new one, or join the vault
/// already sitting in GitHub.
///
/// The app cannot detect an existing vault on its own — the repository and
/// token live in this device's keychain, which is empty until told where to
/// look — so the choice has to be offered.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({
    super.key,
    required this.service,
    required this.settings,
    this.updates,
  });

  final VaultService service;
  final VaultSyncSettings settings;

  /// Passed through to the host list, which shows the update banner.
  final UpdateService? updates;

  Future<void> _createNew(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UnlockScreen(
          service: service,
          settings: settings,
          updates: updates,
          mode: VaultEntryMode.create,
        ),
      ),
    );
  }

  Future<void> _restoreExisting(BuildContext context) async {
    final location = await Navigator.of(context).push<GithubVaultLocation>(
      MaterialPageRoute(builder: (_) => SyncSettingsScreen(settings: settings)),
    );
    if (location == null || !context.mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UnlockScreen(
          service: service,
          settings: settings,
          updates: updates,
          mode: VaultEntryMode.restore,
          restoreFrom: location,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'benterm',
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () => _createNew(context),
                child: const Text('Create a new vault'),
              ),
              const SizedBox(height: 8),
              Text(
                'For your first device.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              OutlinedButton(
                onPressed: () => _restoreExisting(context),
                child: const Text('Use my existing vault'),
              ),
              const SizedBox(height: 8),
              Text(
                'Point this device at the GitHub repo holding your vault and '
                'unlock it with the same passphrase.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
