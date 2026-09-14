import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:benterm/ssh/ssh_host.dart';
import 'package:benterm/ssh/ssh_session.dart';

void main() {
  test('start() fails fast when nothing is listening', () async {
    // Bind then release a port, so the connect is refused rather than
    // hanging on a filtered address.
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();

    final session = SshSession(
      SshHost(hostname: '127.0.0.1', port: port, username: 'nobody'),
    );

    await expectLater(session.start(), throwsA(isA<SocketException>()));
    await session.close();
  });

  test('resize before connect is remembered for the initial pty', () {
    final session = SshSession(
      const SshHost(hostname: 'example.com', username: 'ben'),
    );

    // Must not throw with no shell yet; geometry is applied at shell open.
    session.resize(120, 40, 960, 640);
    session.write('ignored until connected');
  });
}
