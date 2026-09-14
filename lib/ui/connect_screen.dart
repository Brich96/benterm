import 'package:flutter/material.dart';

import 'package:benterm/ssh/echo_session.dart';
import 'package:benterm/ssh/ssh_host.dart';
import 'package:benterm/ssh/ssh_session.dart';
import 'package:benterm/ui/terminal_screen.dart';

enum _AuthMethod { password, privateKey }

/// Ad-hoc connection form. The vault work replaces this with a saved host
/// list; the fields here map one-to-one onto [SshHost].
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _formKey = GlobalKey<FormState>();
  final _hostname = TextEditingController();
  final _port = TextEditingController(text: '22');
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _privateKey = TextEditingController();
  final _keyPassphrase = TextEditingController();

  var _auth = _AuthMethod.password;

  @override
  void dispose() {
    _hostname.dispose();
    _port.dispose();
    _username.dispose();
    _password.dispose();
    _privateKey.dispose();
    _keyPassphrase.dispose();
    super.dispose();
  }

  void _connect() {
    if (!_formKey.currentState!.validate()) return;

    final usingKey = _auth == _AuthMethod.privateKey;
    final host = SshHost(
      hostname: _hostname.text.trim(),
      port: int.parse(_port.text.trim()),
      username: _username.text.trim(),
      password: usingKey ? null : _password.text,
      privateKeyPem: usingKey ? _privateKey.text : null,
      privateKeyPassphrase: usingKey && _keyPassphrase.text.isNotEmpty
          ? _keyPassphrase.text
          : null,
    );

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TerminalScreen(
          session: SshSession(host),
          title: host.displayName,
        ),
      ),
    );
  }

  void _openEchoDemo() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TerminalScreen(
          session: EchoSession(),
          title: 'local echo',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final usingKey = _auth == _AuthMethod.privateKey;

    return Scaffold(
      appBar: AppBar(
        title: const Text('benterm'),
        titleTextStyle: Theme.of(context).textTheme.titleMedium,
        toolbarHeight: 40,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _hostname,
                        decoration: const InputDecoration(
                          labelText: 'Host',
                          hintText: 'example.com',
                        ),
                        autofocus: true,
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
                    maxLines: 5,
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
                    decoration: const InputDecoration(labelText: 'Password'),
                    obscureText: true,
                    onFieldSubmitted: (_) => _connect(),
                  ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _connect,
                  child: const Text('Connect'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _openEchoDemo,
                  child: const Text('Open local echo terminal'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
