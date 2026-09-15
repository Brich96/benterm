import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import 'package:benterm/ssh/host_key.dart';
import 'package:benterm/ssh/ssh_host.dart';
import 'package:benterm/ssh/terminal_session.dart';

/// A real SSH connection behind the [TerminalSession] interface.
///
/// Drop-in replacement for the echo stub: the terminal layer is unchanged.
class SshSession implements TerminalSession {
  SshSession(this.host, {this.pinnedFingerprint, this.onHostKeyPinned});

  final SshHost host;

  /// The fingerprint recorded for this host, or null if never connected.
  final String? pinnedFingerprint;

  /// Called with a newly trusted fingerprint so it can be saved.
  final Future<void> Function(String fingerprint)? onHostKeyPinned;

  /// Set when a key was refused, so the failure can be reported as a
  /// mismatch rather than the generic handshake error dartssh2 throws.
  String? _rejectedFingerprint;

  final _output = StreamController<String>.broadcast();
  final _done = Completer<void>();

  SSHClient? _client;
  SSHSession? _shell;

  /// Geometry reported by the terminal before the pty exists, so the shell
  /// starts at the right size instead of the 80x24 default.
  var _width = 80;
  var _height = 24;
  var _pixelWidth = 0;
  var _pixelHeight = 0;

  @override
  Stream<String> get output => _output.stream;

  @override
  Future<void> get done => _done.future;

  @override
  Future<void> start() async {
    final socket = await SSHSocket.connect(
      host.hostname,
      host.port,
      timeout: const Duration(seconds: 15),
    );

    final pem = host.privateKeyPem;
    final password = host.password;

    final client = SSHClient(
      socket,
      username: host.username,
      identities: pem == null
          ? null
          : SSHKeyPair.fromPem(pem, host.privateKeyPassphrase),
      onPasswordRequest: password == null ? null : () => password,
      onVerifyHostKey: (type, fingerprintBytes) async {
        // dartssh2 hands over the OpenSSH-format fingerprint already:
        // "SHA256:" plus unpadded base64, as UTF-8 bytes.
        final observed = utf8.decode(fingerprintBytes);

        switch (verifyHostKey(
          pinned: pinnedFingerprint,
          observed: observed,
        )) {
          case HostKeyVerdict.firstUse:
            await onHostKeyPinned?.call(observed);
            return true;
          case HostKeyVerdict.matches:
            return true;
          case HostKeyVerdict.mismatch:
            _rejectedFingerprint = observed;
            return false;
        }
      },
    );
    _client = client;

    final SSHSession shell;
    try {
      shell = await client.shell(
        pty: SSHPtyConfig(
          type: 'xterm-256color',
          width: _width,
          height: _height,
          pixelWidth: _pixelWidth,
          pixelHeight: _pixelHeight,
        ),
      );
    } on Exception {
      final rejected = _rejectedFingerprint;
      if (rejected != null) {
        throw HostKeyMismatch(
          endpoint: host.endpoint,
          pinned: pinnedFingerprint!,
          observed: rejected,
        );
      }
      rethrow;
    }
    _shell = shell;

    const decoder = Utf8Decoder(allowMalformed: true);
    decoder.bind(shell.stdout).listen(_emit);
    decoder.bind(shell.stderr).listen(_emit);

    unawaited(
      shell.done.then((_) {
        _emit('\r\n\x1b[90m[connection closed]\x1b[0m\r\n');
        if (!_done.isCompleted) _done.complete();
      }),
    );
  }

  @override
  void write(String data) {
    _shell?.stdin.add(Uint8List.fromList(utf8.encode(data)));
  }

  @override
  void resize(int width, int height, int pixelWidth, int pixelHeight) {
    _width = width;
    _height = height;
    _pixelWidth = pixelWidth;
    _pixelHeight = pixelHeight;
    _shell?.resizeTerminal(width, height, pixelWidth, pixelHeight);
  }

  @override
  Future<void> close() async {
    _shell?.close();
    _client?.close();
    if (!_done.isCompleted) _done.complete();
    await _output.close();
  }

  void _emit(String data) {
    if (!_output.isClosed) _output.add(data);
  }
}
