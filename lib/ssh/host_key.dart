/// What to do with a host key the server just presented.
enum HostKeyVerdict {
  /// Nothing pinned for this endpoint yet: trust it and remember it.
  firstUse,

  /// Matches what was pinned.
  matches,

  /// Differs from what was pinned. Refuse the connection.
  mismatch,
}

/// Compares a server's host key fingerprint against the pinned one.
///
/// Trust on first use, like OpenSSH: the first key seen for an endpoint is
/// recorded, and any later change is refused rather than prompted, because
/// a changed key means either a reinstalled server or an interception, and
/// only the user knows which.
HostKeyVerdict verifyHostKey({
  required String? pinned,
  required String observed,
}) {
  if (pinned == null) return HostKeyVerdict.firstUse;
  return pinned == observed
      ? HostKeyVerdict.matches
      : HostKeyVerdict.mismatch;
}

/// Raised when a server presents a different host key than the pinned one.
class HostKeyMismatch implements Exception {
  const HostKeyMismatch({
    required this.endpoint,
    required this.pinned,
    required this.observed,
  });

  final String endpoint;
  final String pinned;
  final String observed;

  @override
  String toString() =>
      'Host key for $endpoint has changed.\r\n'
      '  expected $pinned\r\n'
      '  received $observed\r\n'
      'This is either a rebuilt server or someone intercepting the '
      'connection. If you are certain the server was rebuilt, delete the '
      'saved host and add it again.';
}
