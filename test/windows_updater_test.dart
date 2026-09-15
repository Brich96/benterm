@TestOn('windows')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:benterm/update/windows_updater.dart';

/// The helper is a separate process, and the way it is launched is the part
/// that has broken before: started detached it inherits no console and no
/// standard handles, so powershell.exe exits without running a line and the
/// update silently never happens. Nothing in the app notices, so the only
/// way to catch that is to launch a real helper and watch it reach its first
/// statement.
void main() {
  late Directory work;

  setUp(() async {
    work = await Directory.systemTemp.createTemp('benterm-updater-test');
  });

  tearDown(() async {
    if (await work.exists()) await work.delete(recursive: true);
  });

  test('the helper process actually starts and runs the script', () async {
    final install = Directory('${work.path}${Platform.pathSeparator}install');
    final staging = Directory('${work.path}${Platform.pathSeparator}staging');
    await install.create(recursive: true);
    await staging.create(recursive: true);

    final log = File(
      '${Platform.environment['TEMP']}${Platform.pathSeparator}'
      'benterm-update.log',
    );
    final before = await log.exists() ? await log.length() : 0;

    final updater = WindowsUpdater(
      installDirectory: install,
      executablePath: '${install.path}${Platform.pathSeparator}benterm.exe',
    );

    // The helper waits for this process to exit before touching anything, so
    // it will still be sitting there when the assertion runs; killing it
    // leaves both directories untouched.
    final helper = await updater.applyAndExit(
      staging: staging,
      relaunch: false,
    );
    addTearDown(helper.kill);

    // It logs before it starts waiting, so its own staging path showing up
    // proves the script ran.
    var logged = '';
    for (var attempt = 0; attempt < 40; attempt++) {
      if (await log.exists()) {
        logged = await log.readAsString();
        if (logged.length > before && logged.contains(staging.path)) break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }

    expect(
      logged.substring(before.clamp(0, logged.length)),
      contains(staging.path),
      reason: 'the helper never ran; check how the process is started',
    );
  });
}
