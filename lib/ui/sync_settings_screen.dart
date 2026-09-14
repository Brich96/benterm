import 'package:flutter/material.dart';

import 'package:benterm/vault/github_vault_store.dart';
import 'package:benterm/vault/secret_store.dart';

/// Where the encrypted vault syncs to. The token is held in the platform
/// keychain, never in the vault blob itself.
class SyncSettingsScreen extends StatefulWidget {
  const SyncSettingsScreen({
    super.key,
    required this.settings,
    this.current,
  });

  final VaultSyncSettings settings;
  final GithubVaultLocation? current;

  @override
  State<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends State<SyncSettingsScreen> {
  final _formKey = GlobalKey<FormState>();

  late final _owner = TextEditingController(text: widget.current?.owner ?? '');
  late final _repo = TextEditingController(text: widget.current?.repo ?? '');
  late final _path = TextEditingController(
    text: widget.current?.path ?? 'vault.json',
  );
  late final _token = TextEditingController(text: widget.current?.token ?? '');

  @override
  void dispose() {
    _owner.dispose();
    _repo.dispose();
    _path.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final location = GithubVaultLocation(
      owner: _owner.text.trim(),
      repo: _repo.text.trim(),
      token: _token.text.trim(),
      path: _path.text.trim(),
    );

    await widget.settings.save(location);
    if (!mounted) return;
    Navigator.of(context).pop(location);
  }

  String? _required(String? value) =>
      (value == null || value.trim().isEmpty) ? 'Required' : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GitHub sync'),
        titleTextStyle: Theme.of(context).textTheme.titleMedium,
        toolbarHeight: 40,
        actions: [
          TextButton(onPressed: _save, child: const Text('Save')),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  'The vault is stored as one encrypted file in a private '
                  'repo. Use a fine-grained token limited to that repo with '
                  'read and write access to contents.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _owner,
                  decoration: const InputDecoration(
                    labelText: 'Owner',
                    hintText: 'your-github-username',
                  ),
                  autofocus: true,
                  validator: _required,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _repo,
                  decoration: const InputDecoration(
                    labelText: 'Repository',
                    hintText: 'ssh-vault',
                  ),
                  validator: _required,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _path,
                  decoration: const InputDecoration(labelText: 'File path'),
                  validator: _required,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _token,
                  decoration: const InputDecoration(
                    labelText: 'Access token',
                    hintText: 'github_pat_...',
                  ),
                  obscureText: true,
                  validator: _required,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
