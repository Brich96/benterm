import 'package:flutter/material.dart';

import 'package:benterm/ssh/ssh_host.dart';
import 'package:benterm/ui/sessions_screen.dart';
import 'package:benterm/ui/update_banner.dart';
import 'package:benterm/vault/github_vault_store.dart';
import 'package:benterm/vault/secret_store.dart';
import 'package:benterm/update/update_service.dart';
import 'package:benterm/vault/vault_service.dart';
import 'package:benterm/ui/connect_screen.dart';
import 'package:benterm/ui/host_edit_screen.dart';
import 'package:benterm/ui/sync_settings_screen.dart';

/// The saved hosts in the vault: connect, edit, and sync with GitHub.
class HostListScreen extends StatefulWidget {
  const HostListScreen({
    super.key,
    required this.service,
    required this.settings,
    this.updates,
  });

  final VaultService service;
  final VaultSyncSettings settings;

  /// Null in tests and wherever self-updating does not apply.
  final UpdateService? updates;

  @override
  State<HostListScreen> createState() => _HostListScreenState();
}

class _HostListScreenState extends State<HostListScreen> {
  final _search = TextEditingController();

  GithubVaultLocation? _location;
  var _syncing = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Hosts matching the search box, by label, user, hostname or port.
  List<SshHost> get _visibleHosts {
    final query = _search.text.trim().toLowerCase();
    final hosts = widget.service.vault.hosts;
    if (query.isEmpty) return hosts;

    return [
      for (final host in hosts)
        if ('${host.label ?? ''} ${host.username}@${host.hostname}:${host.port}'
            .toLowerCase()
            .contains(query))
          host,
    ];
  }

  @override
  void initState() {
    super.initState();
    _loadLocation();
  }

  Future<void> _loadLocation() async {
    final location = await widget.settings.load();
    if (mounted) setState(() => _location = location);
  }

  void _connect(SshHost host) {
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => SessionsScreen(host: host, service: widget.service),
          ),
        )
        // Host keys pinned during the session change what the list shows.
        .then((_) {
          if (mounted) setState(() {});
        });
  }

  Future<void> _addHost() async {
    final host = await Navigator.of(
      context,
    ).push<SshHost>(MaterialPageRoute(builder: (_) => const HostEditScreen()));
    if (host == null) return;

    await widget.service.upsertHost(host);
    if (mounted) setState(() {});
  }

  Future<void> _editHost(SshHost host) async {
    final edited = await Navigator.of(context).push<SshHost>(
      MaterialPageRoute(builder: (_) => HostEditScreen(host: host)),
    );
    if (edited == null) return;

    await widget.service.upsertHost(edited);
    if (mounted) setState(() {});
  }

  Future<void> _deleteHost(SshHost host) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${host.displayName}?'),
        content: const Text(
          'This removes the host and its stored credentials from the vault '
          'on every device at the next sync.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await widget.service.removeHost(host.id);
    if (mounted) setState(() {});
  }

  Future<void> _openSyncSettings() async {
    final location = await Navigator.of(context).push<GithubVaultLocation>(
      MaterialPageRoute(
        builder: (_) =>
            SyncSettingsScreen(settings: widget.settings, current: _location),
      ),
    );
    if (location != null && mounted) setState(() => _location = location);
  }

  Future<void> _sync() async {
    final location = _location;
    if (location == null) {
      await _openSyncSettings();
      return;
    }

    setState(() => _syncing = true);
    try {
      final outcome = await widget.service.sync(location: location);
      _report(switch (outcome) {
        SyncOutcome.created => 'Vault created on GitHub',
        SyncOutcome.pushed => 'Changes pushed',
        SyncOutcome.pulled => 'Pulled changes from GitHub',
        SyncOutcome.upToDate => 'Already up to date',
      });
    } on VaultConflict {
      await _resolveConflict(location);
    } on GithubVaultError catch (error) {
      _report('Sync failed: ${error.message}');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  /// Both sides changed. The user picks a winner; nothing is merged, since a
  /// wrong automatic merge here would silently lose credentials.
  Future<void> _resolveConflict(GithubVaultLocation location) async {
    final keepMine = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sync conflict'),
        content: const Text(
          'This device and GitHub both changed since the last sync. Keep one '
          'copy; the other is discarded.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Take GitHub copy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Keep this device'),
          ),
        ],
      ),
    );

    if (keepMine == null) return;

    try {
      if (keepMine) {
        await widget.service.pushOverwritingRemote(location);
        _report('GitHub overwritten with this device');
      } else {
        await widget.service.pullDiscardingLocalChanges(location);
        _report('Took the GitHub copy');
      }
      if (mounted) setState(() {});
    } on GithubVaultError catch (error) {
      _report('Sync failed: ${error.message}');
    }
  }

  void _report(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final allHosts = widget.service.vault.hosts;
    final hosts = _visibleHosts;
    final unpushed = widget.service.hasUnpushedChanges;
    // Searching is only worth the space once the list outgrows the screen.
    final searchable = allHosts.length > 5;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hosts'),
        titleTextStyle: Theme.of(context).textTheme.titleMedium,
        toolbarHeight: 40,
        actions: [
          IconButton(
            tooltip: _location == null
                ? 'Set up GitHub sync'
                : unpushed
                ? 'Sync (unpushed changes)'
                : 'Sync',
            onPressed: _syncing ? null : _sync,
            icon: _syncing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Badge(
                    isLabelVisible: unpushed && _location != null,
                    child: const Icon(Icons.sync),
                  ),
          ),
          IconButton(
            tooltip: 'GitHub sync settings',
            onPressed: _openSyncSettings,
            icon: const Icon(Icons.settings),
          ),
          IconButton(
            tooltip: 'Quick connect (not saved)',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ConnectScreen(service: widget.service),
              ),
            ),
            icon: const Icon(Icons.bolt),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addHost,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          if (widget.updates != null) UpdateBanner(service: widget.updates!),
          Expanded(
            child: allHosts.isEmpty
                ? _EmptyState(onAdd: _addHost)
                : Column(
                    children: [
                      if (searchable)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                          child: TextField(
                            controller: _search,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              isDense: true,
                              prefixIcon: const Icon(Icons.search, size: 18),
                              hintText: 'Search hosts',
                              border: const OutlineInputBorder(),
                              suffixIcon: _search.text.isEmpty
                                  ? null
                                  : IconButton(
                                      icon: const Icon(Icons.clear, size: 18),
                                      onPressed: () => setState(_search.clear),
                                    ),
                            ),
                          ),
                        ),
                      if (hosts.isEmpty)
                        const Expanded(
                          child: Center(
                            child: Text('No hosts match that search'),
                          ),
                        )
                      else
                        Expanded(child: _hostList(hosts)),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _hostList(List<SshHost> hosts) {
    return ListView.builder(
      itemCount: hosts.length,
      itemBuilder: (context, index) {
        final host = hosts[index];
        return ListTile(
          leading: const Icon(Icons.dns_outlined),
          title: Text(host.displayName),
          subtitle: Text(
            '${host.username}@${host.hostname}:${host.port}'
            '${host.privateKeyPem != null ? '  ·  key' : ''}',
          ),
          onTap: () => _connect(host),
          trailing: PopupMenuButton<String>(
            onSelected: (value) => switch (value) {
              'edit' => _editHost(host),
              'delete' => _deleteHost(host),
              _ => null,
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('No hosts yet', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Hosts you add are encrypted in your vault.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Add a host'),
          ),
        ],
      ),
    );
  }
}
