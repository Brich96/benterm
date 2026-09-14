import 'package:flutter/material.dart';

import 'package:benterm/vault/secret_store.dart';
import 'package:benterm/vault/vault_crypto.dart';
import 'package:benterm/vault/vault_service.dart';
import 'package:benterm/ui/host_list_screen.dart';

/// Passphrase gate. On a device with no vault yet this creates one; on a
/// device that already has a vault it unlocks it.
class UnlockScreen extends StatefulWidget {
  const UnlockScreen({
    super.key,
    required this.service,
    required this.settings,
    required this.hasExistingVault,
  });

  final VaultService service;
  final VaultSyncSettings settings;

  /// Whether an encrypted vault is already stored on this device.
  final bool hasExistingVault;

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passphrase = TextEditingController();
  final _confirm = TextEditingController();

  String? _error;
  var _busy = false;

  bool get _creating => !widget.hasExistingVault;

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
      await widget.service.unlock(_passphrase.text);
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
      setState(() => _error = 'Wrong passphrase');
    } on UnreadableVault catch (error) {
      setState(() => _error = error.reason);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                  _creating ? 'Create your vault' : 'Unlock benterm',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  _creating
                      ? 'This passphrase encrypts your hosts and keys. It is '
                            'never stored or sent anywhere, so it cannot be '
                            'recovered.'
                      : 'Enter your vault passphrase.',
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
                  child: Text(_creating ? 'Create vault' : 'Unlock'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
