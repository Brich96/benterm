import 'package:flutter/material.dart';

import 'package:benterm/vault/github_vault_store.dart';
import 'package:benterm/vault/secret_store.dart';
import 'package:benterm/vault/vault_crypto.dart';
import 'package:benterm/vault/vault_service.dart';
import 'package:benterm/ui/host_list_screen.dart';

enum VaultEntryMode {
  /// No vault anywhere yet: pick a passphrase and confirm it.
  create,

  /// This device already holds an encrypted vault.
  unlock,

  /// A vault exists on GitHub and this device is joining it.
  restore,
}

/// Passphrase gate for all three ways into the vault.
class UnlockScreen extends StatefulWidget {
  const UnlockScreen({
    super.key,
    required this.service,
    required this.settings,
    required this.mode,
    this.restoreFrom,
  });

  final VaultService service;
  final VaultSyncSettings settings;
  final VaultEntryMode mode;

  /// Where to pull the vault from, for [VaultEntryMode.restore].
  final GithubVaultLocation? restoreFrom;

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passphrase = TextEditingController();
  final _confirm = TextEditingController();

  String? _error;
  var _busy = false;

  bool get _creating => widget.mode == VaultEntryMode.create;

  @override
  void dispose() {
    _passphrase.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      if (widget.mode == VaultEntryMode.restore) {
        await widget.service.restoreFromRemote(
          widget.restoreFrom!,
          _passphrase.text,
        );
      } else {
        await widget.service.unlock(_passphrase.text);
      }

      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => HostListScreen(
            service: widget.service,
            settings: widget.settings,
          ),
        ),
      );
    } on WrongVaultPassphrase {
      setState(() => _error = 'Wrong passphrase for that vault');
    } on UnreadableVault catch (error) {
      setState(() => _error = error.reason);
    } on NoRemoteVault {
      setState(
        () => _error = 'No vault found in that repository. Check the repo '
            'and file path, or create a new vault instead.',
      );
    } on GithubVaultError catch (error) {
      setState(() => _error = 'GitHub: ${error.message}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _title => switch (widget.mode) {
    VaultEntryMode.create => 'Create your vault',
    VaultEntryMode.unlock => 'Unlock benterm',
    VaultEntryMode.restore => 'Unlock your existing vault',
  };

  String get _blurb => switch (widget.mode) {
    VaultEntryMode.create =>
      'This passphrase encrypts your hosts and keys. It is never stored or '
          'sent anywhere, so it cannot be recovered.',
    VaultEntryMode.unlock => 'Enter your vault passphrase.',
    VaultEntryMode.restore =>
      'Enter the same passphrase you used on your other device. It decrypts '
          'the vault locally; nothing checks it against a server.',
  };

  String get _action => switch (widget.mode) {
    VaultEntryMode.create => 'Create vault',
    VaultEntryMode.unlock => 'Unlock',
    VaultEntryMode.restore => 'Unlock and sync',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.mode == VaultEntryMode.unlock
          ? null
          : AppBar(toolbarHeight: 40),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Form(
            key: _formKey,
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  _title,
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  _blurb,
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _passphrase,
                  decoration: const InputDecoration(labelText: 'Passphrase'),
                  obscureText: true,
                  autofocus: true,
                  onFieldSubmitted: (_) => _submit(),
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Required';
                    if (_creating && value.length < 8) {
                      return 'Use at least 8 characters';
                    }
                    return null;
                  },
                ),
                if (_creating) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _confirm,
                    decoration: const InputDecoration(
                      labelText: 'Confirm passphrase',
                    ),
                    obscureText: true,
                    onFieldSubmitted: (_) => _submit(),
                    validator: (value) => value == _passphrase.text
                        ? null
                        : 'Passphrases do not match',
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_action),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
