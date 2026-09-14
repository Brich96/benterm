import 'package:flutter/material.dart';

import 'package:benterm/ssh/ssh_host.dart';

enum _AuthMethod { password, privateKey }

/// Add or edit a stored host. Returns the edited [SshHost] to the caller,
/// which is responsible for saving it into the vault.
class HostEditScreen extends StatefulWidget {
  const HostEditScreen({super.key, this.host});

  /// Null when adding a new host.
  final SshHost? host;

  @override
  State<HostEditScreen> createState() => _HostEditScreenState();
}

class _HostEditScreenState extends State<HostEditScreen> {
  final _formKey = GlobalKey<FormState>();

  late final _label = TextEditingController(text: widget.host?.label ?? '');
  late final _hostname = TextEditingController(
    text: widget.host?.hostname ?? '',
  );
  late final _port = TextEditingController(
    text: '${widget.host?.port ?? 22}',
  );
  late final _username = TextEditingController(
    text: widget.host?.username ?? '',
  );
  late final _password = TextEditingController(
    text: widget.host?.password ?? '',
  );
  late final _privateKey = TextEditingController(
    text: widget.host?.privateKeyPem ?? '',
  );
  late final _keyPassphrase = TextEditingController(
    text: widget.host?.privateKeyPassphrase ?? '',
  );

  late var _auth = widget.host?.privateKeyPem == null
      ? _AuthMethod.password
      : _AuthMethod.privateKey;

  @override
  void dispose() {
    _label.dispose();
    _hostname.dispose();
    _port.dispose();
    _username.dispose();
    _password.dispose();
    _privateKey.dispose();
    _keyPassphrase.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    final usingKey = _auth == _AuthMethod.privateKey;
    final label = _label.text.trim();

    final existing = widget.host;
    final host = SshHost(
      id: existing?.id ?? SshHost.newId(),
      hostname: _hostname.text.trim(),
      port: int.parse(_port.text.trim()),
      username: _username.text.trim(),
      label: label.isEmpty ? null : label,
      password: usingKey || _password.text.isEmpty ? null : _password.text,
      privateKeyPem: usingKey ? _privateKey.text : null,
      privateKeyPassphrase: usingKey && _keyPassphrase.text.isNotEmpty
          ? _keyPassphrase.text
          : null,
    );

    Navigator.of(context).pop(host);
  }

  @override
  Widget build(BuildContext context) {
    final usingKey = _auth == _AuthMethod.privateKey;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.host == null ? 'Add host' : 'Edit host'),
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
                TextFormField(
                  controller: _label,
                  decoration: const InputDecoration(
                    labelText: 'Label (optional)',
                    hintText: 'prod web',
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _hostname,
                        decoration: const InputDecoration(labelText: 'Host'),
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                            ? 'Required'
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _port,
                        decoration: const InputDecoration(labelText: 'Port'),
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          final port = int.tryParse(value?.trim() ?? '');
                          if (port == null || port < 1 || port > 65535) {
                            return '1-65535';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _username,
                  decoration: const InputDecoration(labelText: 'Username'),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Required'
                      : null,
                ),
                const SizedBox(height: 24),
                SegmentedButton<_AuthMethod>(
                  segments: const [
                    ButtonSegment(
                      value: _AuthMethod.password,
                      label: Text('Password'),
                    ),
                    ButtonSegment(
                      value: _AuthMethod.privateKey,
                      label: Text('Private key'),
                    ),
                  ],
                  selected: {_auth},
                  onSelectionChanged: (selection) =>
                      setState(() => _auth = selection.first),
                ),
                const SizedBox(height: 16),
                if (usingKey) ...[
                  TextFormField(
                    controller: _privateKey,
                    decoration: const InputDecoration(
                      labelText: 'Private key (PEM)',
                      hintText: '-----BEGIN OPENSSH PRIVATE KEY-----',
                      alignLabelWithHint: true,
                    ),
                    maxLines: 6,
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                        ? 'Paste a private key'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _keyPassphrase,
                    decoration: const InputDecoration(
                      labelText: 'Key passphrase (optional)',
                    ),
                    obscureText: true,
                  ),
                ] else
                  TextFormField(
                    controller: _password,
                    decoration: const InputDecoration(
                      labelText: 'Password (optional)',
                      helperText: 'Leave empty to be prompted on connect',
                    ),
                    obscureText: true,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
