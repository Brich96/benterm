import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'package:benterm/update/release_check.dart';
import 'package:benterm/update/update_downloader.dart';
import 'package:benterm/update/windows_updater.dart';

/// How an update can be applied on this platform.
enum UpdateStyle {
  /// Files are swapped by a helper process: can restart now, or on exit.
  replaceFiles,

  /// The system installer takes over and asks the user to confirm.
  systemInstaller,

  /// Nothing to do here; direct the user to the release page.
  unsupported,
}

/// Raised when the install cannot be written without elevation.
class InstallNotWritable implements Exception {
  const InstallNotWritable(this.path);

  final String path;

  @override
  String toString() =>
      'benterm cannot update itself because $path is not writable. '
      'Move the folder somewhere writable, such as under your user folder.';
}

/// Finds, downloads and applies updates.
class UpdateService {
  UpdateService({
    ReleaseCheck? releaseCheck,
    UpdateDownloader? downloader,
    WindowsUpdater? windowsUpdater,
    this.currentVersionOverride,
  }) : _check = releaseCheck ?? ReleaseCheck(),
       _downloader = downloader ?? UpdateDownloader(),
       _windows = windowsUpdater ?? WindowsUpdater();

  static const _installerChannel = MethodChannel('benterm/installer');

  final ReleaseCheck _check;
  final UpdateDownloader _downloader;
  final WindowsUpdater _windows;

  /// Set by tests; otherwise the version is read from the running bundle.
  final String? currentVersionOverride;

  String? _cachedVersion;

  /// Staged download waiting to be applied, if any.
  Directory? _staged;

  bool get hasStagedUpdate => _staged != null;

  /// Set when the user chose to install on close, so the exit path knows to
  /// run the swap.
  var installOnExit = false;

  static UpdateStyle get style {
    if (kIsWeb) return UpdateStyle.unsupported;
    if (Platform.isWindows) return UpdateStyle.replaceFiles;
    if (Platform.isAndroid) return UpdateStyle.systemInstaller;
    return UpdateStyle.unsupported;
  }

  /// The version of the running build.
  Future<String> currentVersion() async {
    if (currentVersionOverride != null) return currentVersionOverride!;
    return _cachedVersion ??= (await PackageInfo.fromPlatform()).version;
  }

  /// The release to offer, or null when already up to date.
  Future<ReleaseInfo?> check() async => _check.newerThan(await currentVersion());

  /// The file this platform installs from.
  String? assetNameFor(ReleaseInfo release) => switch (style) {
    UpdateStyle.replaceFiles => 'benterm-windows-x64.zip',
    UpdateStyle.systemInstaller => 'benterm-android.apk',
    UpdateStyle.unsupported => null,
  };

  /// Downloads [release] and prepares it, without applying anything yet.
  ///
  /// Returns the downloaded file so the caller can install it later; on
  /// Windows the archive is unpacked ready for the swap.
  Future<File> stage(
    ReleaseInfo release, {
    void Function(int received, int total)? onProgress,
  }) async {
    final name = assetNameFor(release);
    if (name == null) throw const MissingReleaseAsset('an installable file');

    final asset = release.assetNamed(name);
    if (asset == null) throw MissingReleaseAsset(name);

    if (style == UpdateStyle.replaceFiles &&
        !await _windows.canReplaceInstall()) {
      throw InstallNotWritable(_windows.installDirectory.path);
    }

    final digests = await _downloader.checksums(release);
    final into = Directory(
      '${(await getTemporaryDirectory()).path}'
      '${Platform.pathSeparator}benterm-update'
      '${Platform.pathSeparator}${release.version}',
    );

    final file = await _downloader.download(
      asset,
      into: into,
      expected: digests[name],
      onProgress: onProgress,
    );

    if (style == UpdateStyle.replaceFiles) {
      _staged = await _windows.stage(
        file,
        into: Directory('${into.path}${Platform.pathSeparator}unpacked'),
      );
    }

    return file;
  }

  /// Applies a staged Windows update and quits so the swap can run.
  ///
  /// Nothing after this call runs: the app must exit for its files to be
  /// replaceable.
  Future<void> applyNow() async {
    final staged = _staged;
    if (staged == null) return;

    await _windows.applyAndExit(staging: staged, relaunch: true);
    exit(0);
  }

  /// Applies a staged update after the app closes, without restarting it.
  ///
  /// Call from the app's exit path; the helper waits for this process to go
  /// away before touching anything.
  Future<void> applyOnExit() async {
    final staged = _staged;
    if (staged == null) return;
    await _windows.applyAndExit(staging: staged, relaunch: false);
  }

  /// Hands a downloaded APK to Android's installer.
  Future<void> installApk(File apk) async {
    await _installerChannel.invokeMethod<bool>('installApk', {
      'path': apk.path,
    });
  }

  /// Whether Android will let the app start an install at all.
  Future<bool> canRequestInstalls() async {
    if (style != UpdateStyle.systemInstaller) return true;
    return await _installerChannel.invokeMethod<bool>('canRequestInstalls') ??
        false;
  }

  void close() {
    _check.close();
    _downloader.close();
  }
}
