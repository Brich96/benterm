import 'package:flutter/material.dart';

import 'package:benterm/ssh/session_factory.dart';
import 'package:benterm/ssh/ssh_host.dart';
import 'package:benterm/ssh/terminal_session.dart';
import 'package:benterm/terminal/terminal_pane.dart';
import 'package:benterm/vault/vault_service.dart';

class _OpenSession {
  _OpenSession({required this.title, required this.session})
    : key = UniqueKey();

  final String title;
  final TerminalSession session;

  /// Keeps each pane's state tied to its session as tabs come and go.
  final Key key;
}

/// Holds several live terminals at once.
///
/// Panes live in an [IndexedStack] rather than a [TabBarView] so that a
/// background session keeps running and its scrollback survives: rebuilding
/// a pane would drop the SSH connection behind it.
class SessionsScreen extends StatefulWidget {
  const SessionsScreen({
    super.key,
    required this.host,
    required this.service,
    this.sessionBuilder,
  });

  /// The connection to open first.
  final SshHost host;

  final VaultService? service;

  /// Overridable so tests can open panes without touching the network.
  final TerminalSession Function(SshHost host)? sessionBuilder;

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  late final List<_OpenSession> _sessions = [
    _OpenSession(
      title: widget.host.displayName,
      session: _sessionFor(widget.host),
    ),
  ];

  var _current = 0;

  TerminalSession _sessionFor(SshHost host) =>
      widget.sessionBuilder?.call(host) ?? sessionFor(host, widget.service);

  Future<void> _addSession() async {
    final service = widget.service;
    if (service == null) return;

    final hosts = service.vault.hosts;
    if (hosts.isEmpty) return;

    final host = await showModalBottomSheet<SshHost>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(dense: true, title: Text('Open another session')),
            const Divider(height: 1),
            for (final host in hosts)
              ListTile(
                leading: const Icon(Icons.dns_outlined),
                title: Text(host.displayName),
                subtitle: Text(
                  '${host.username}@${host.hostname}:${host.port}',
                ),
                onTap: () => Navigator.of(context).pop(host),
              ),
          ],
        ),
      ),
    );

    if (host == null) return;
    setState(() {
      _sessions.add(
        _OpenSession(title: host.displayName, session: _sessionFor(host)),
      );
      _current = _sessions.length - 1;
    });
  }

  void _closeSession(int index) {
    // Removing the pane disposes it, which closes the session underneath.
    setState(() {
      _sessions.removeAt(index);
      if (_current >= _sessions.length) _current = _sessions.length - 1;
    });

    if (_sessions.isEmpty) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    if (_sessions.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final single = _sessions.length == 1;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 40,
        titleSpacing: 0,
        title: single
            ? Text(_sessions.first.title, style: theme.textTheme.titleMedium)
            : SizedBox(
                height: 40,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _sessions.length,
                  itemBuilder: (context, index) {
                    final selected = index == _current;
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 2,
                        vertical: 4,
                      ),
                      child: InkWell(
                        onTap: () => setState(() => _current = index),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.only(left: 12, right: 4),
                          decoration: BoxDecoration(
                            color: selected
                                ? theme.colorScheme.primaryContainer
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              Text(
                                _sessions[index].title,
                                style: theme.textTheme.bodySmall,
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, size: 14),
                                visualDensity: VisualDensity.compact,
                                tooltip: 'Close session',
                                onPressed: () => _closeSession(index),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
        actions: [
          if (widget.service != null)
            IconButton(
              tooltip: 'Open another session',
              onPressed: _addSession,
              icon: const Icon(Icons.add),
            ),
          if (single)
            IconButton(
              tooltip: 'Close session',
              onPressed: () => _closeSession(0),
              icon: const Icon(Icons.close),
            ),
        ],
      ),
      body: IndexedStack(
        index: _current,
        children: [
          for (final session in _sessions)
            TerminalPane(key: session.key, session: session.session),
        ],
      ),
    );
  }
}
