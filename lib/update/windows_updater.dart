import 'dart:io';

import 'package:archive/archive_io.dart';

/// Replaces the installed files on Windows.
///
/// A running executable cannot overwrite itself, so the swap is done by a
/// short PowerShell script that waits for this process to exit first. The
/// script moves the current files aside before copying the new ones in, and
/// puts them back if the copy fails, so a failed update leaves a working
/// install rather than a half-written one.
class WindowsUpdater {
  WindowsUpdater({Directory? installDirectory, String? executablePath})
    : _installOverride = installDirectory,
      _executableOverride = executablePath;

  final Directory? _installOverride;
  final String? _executableOverride;

  String get executablePath =>
      _executableOverride ?? Platform.resolvedExecutable;

  Directory get installDirectory =>
      _installOverride ?? File(executablePath).parent;

  /// Whether the install can be replaced without elevation.
  ///
  /// A zip extracted into Program Files cannot, and saying so up front is
  /// better than failing halfway through a swap.
  Future<bool> canReplaceInstall() async {
    final probe = File(
      '${installDirectory.path}${Platform.pathSeparator}.benterm-write-test',
    );
    try {
      await probe.writeAsString('', flush: true);
      await probe.delete();
      return true;
    } on FileSystemException {
      return false;
    }
  }

  /// Unpacks the downloaded zip into a staging directory beside it.
  Future<Directory> stage(File archive, {required Directory into}) async {
    if (await into.exists()) await into.delete(recursive: true);
    await into.create(recursive: true);

    await extractFileToDisk(archive.path, into.path);

    // The zip holds the contents of the Release folder, so the executable
    // should be at the top level. If a future build nests it, unwrap it.
    final entries = await into.list().toList();
    if (entries.length == 1 && entries.single is Directory) {
      return entries.single as Directory;
    }
    return into;
  }

  /// Starts the swap and returns once the helper is running.
  ///
  /// The caller must exit immediately afterwards: the helper waits for this
  /// process to go away before touching any files.
  Future<void> applyAndExit({
    required Directory staging,
    required bool relaunch,
  }) async {
    final script = await _writeScript();

    await Process.start(
      'powershell.exe',
      [
        '-NoProfile',
        '-NonInteractive',
        '-WindowStyle',
        'Hidden',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        script.path,
        '-TargetPid',
        '$pid',
        '-Staging',
        staging.path,
        '-InstallDir',
        installDirectory.path,
        '-Exe',
        executablePath,
        if (relaunch) '-Relaunch',
      ],
      mode: ProcessStartMode.detached,
    );
  }

  Future<File> _writeScript() async {
    final script = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'benterm-apply-update.ps1',
    );
    await script.writeAsString(_swapScript, flush: true);
    return script;
  }
}

const _swapScript = r'''
param(
  [Parameter(Mandatory=$true)][int]$TargetPid,
  [Parameter(Mandatory=$true)][string]$Staging,
  [Parameter(Mandatory=$true)][string]$InstallDir,
  [Parameter(Mandatory=$true)][string]$Exe,
  [switch]$Relaunch
)

$ErrorActionPreference = 'Stop'

# The app still holds its own executable open; wait for it to go.
try {
  Wait-Process -Id $TargetPid -Timeout 120 -ErrorAction Stop
} catch [System.TimeoutException] {
  exit 2
} catch {
  # Already gone, which is what we wanted.
}

# Give Windows a moment to release the file handles.
Start-Sleep -Milliseconds 500

$backup = Join-Path $env:TEMP ("benterm-previous-" + [System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $backup | Out-Null

try {
  # Move the old install aside rather than deleting it, so a failed copy
  # can be undone.
  Get-ChildItem -LiteralPath $InstallDir -Force | ForEach-Object {
    Move-Item -LiteralPath $_.FullName -Destination $backup -Force
  }
  Copy-Item -Path (Join-Path $Staging '*') -Destination $InstallDir -Recurse -Force
} catch {
  # Put everything back exactly as it was.
  Get-ChildItem -LiteralPath $InstallDir -Force -ErrorAction SilentlyContinue |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
  Get-ChildItem -LiteralPath $backup -Force | ForEach-Object {
    Move-Item -LiteralPath $_.FullName -Destination $InstallDir -Force
  }
  Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction SilentlyContinue
  exit 1
}

Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $Staging -Recurse -Force -ErrorAction SilentlyContinue

if ($Relaunch) {
  Start-Process -FilePath $Exe
}
''';
