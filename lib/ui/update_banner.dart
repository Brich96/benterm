import 'dart:io';

import 'package:flutter/material.dart';

import 'package:benterm/update/release_check.dart';
import 'package:benterm/update/update_downloader.dart';
import 'package:benterm/update/update_service.dart';

/// Announces a newer release and offers to install it.
///
/// Stays invisible unless there is something to offer, and a failed check is
/// silent: the app works fine without updating, so a network blip should not
/// produce an error the user has to dismiss.
class UpdateBanner extends StatefulWidget {
  const UpdateBanner({super.key, required this.service});

  final UpdateService service;

  @override
  State<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<UpdateBanner> {
  ReleaseInfo? _available;
  var _dismissed = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final release = await widget.service.check();
      if (mounted && release != null) setState(() => _available = release);
    } on Object {
      // Offline, rate limited, or GitHub is down: nothing worth saying.
    }
  }

  Future<void> _openDialog() async {
    final release = _available;
    if (release == null) return;

    final handled = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          _UpdateDialog(service: widget.service, release: release),
    );

    if (handled == true && mounted) setState(() => _dismissed = true);
  }

  @override
  Widget build(BuildContext context) {
    final release = _available;
    if (release == null || _dismissed) return const SizedBox.shrink();

    final colors = Theme.of(context).colorScheme;

    return Material(
      color: colors.secondaryContainer,
      child: InkWell(
        onTap: _openDialog,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.system_update,
                size: 18,
                color: colors.onSecondaryContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Version ${release.version} is available',
                  style: TextStyle(color: colors.onSecondaryContainer),
                ),
              ),
              TextButton(onPressed: _openDialog, child: const Text('View')),
              IconButton(
                tooltip: 'Dismiss',
                iconSize: 18,
                onPressed: () => setState(() => _dismissed = true),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.service, required this.release});

  final UpdateService service;
  final ReleaseInfo release;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  double? _progress;
  String? _error;
  var _busy = false;

  /// Deferring to app exit only means anything where the update is a file
  /// swap. Android hands over to the system installer immediately.
  bool get _canInstallOnExit => UpdateService.style == UpdateStyle.replaceFiles;

  Future<File?> _download() async {
    setState(() {
      _busy = true;
      _error = null;
      _progress = 0;
    });

    try {
      return await widget.service.stage(
        widget.release,
        onProgress: (received, total) {
          if (mounted && total > 0) {
            setState(() => _progress = received / total);
          }
        },
      );
    } on ChecksumMismatch catch (error) {
      setState(() => _error = '$error');
    } on InstallNotWritable catch (error) {
      setState(() => _error = '$error');
    } on MissingReleaseAsset catch (error) {
      setState(() => _error = '$error');
    } on Object catch (error) {
      setState(() => _error = 'Download failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    return null;
  }

  Future<void> _updateNow() async {
    final file = await _download();
    if (file == null || !mounted) return;

    switch (UpdateService.style) {
      case UpdateStyle.replaceFiles:
        // Does not return: the app exits so its files can be replaced.
        await widget.service.applyNow();
      case UpdateStyle.systemInstaller:
        if (!await widget.service.canRequestInstalls()) {
          if (!mounted) return;
          setState(
            () => _error =
                'Android needs permission to install apps from BenTerm. '
                'Allow it in the screen that opens, then try again.',
          );
        }
        await widget.service.installApk(file);
        if (mounted) Navigator.of(context).pop(true);
      case UpdateStyle.unsupported:
        break;
    }
  }

  Future<void> _installOnExit() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final file = await _download();
    if (file == null || !mounted) return;

    widget.service.installOnExit = true;
    navigator.pop(true);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Update will be installed when you close BenTerm'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final notes = widget.release.notes.trim();

    return AlertDialog(
      title: Text('BenTerm ${widget.release.version}'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (notes.isNotEmpty)
              Flexible(
                child: SingleChildScrollView(
                  child: Text(
                    notes,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            if (_busy) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 8),
              Text(
                _progress == null
                    ? 'Downloading...'
                    : 'Downloading ${((_progress ?? 0) * 100).round()}%',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Later'),
        ),
        if (_canInstallOnExit)
          TextButton(
            onPressed: _busy ? null : _installOnExit,
            child: const Text('Install on exit'),
          ),
        FilledButton(
          onPressed: _busy ? null : _updateNow,
          child: const Text('Update now'),
        ),
      ],
    );
  }
}
