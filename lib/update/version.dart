/// Semantic version comparison, kept apart from any networking so it can be
/// tested exhaustively.
///
/// Only the numeric release part is compared. A pre-release suffix
/// (`1.2.0-beta.1`) is treated as equal to its release, which is fine here
/// because pre-releases are never published as updates.
class Version implements Comparable<Version> {
  const Version(this.major, this.minor, this.patch);

  /// Parses `1.2.3`, tolerating a leading `v` and any `-suffix`/`+build`.
  ///
  /// Returns null for anything that is not a version, so a stray tag in the
  /// repository cannot be mistaken for a release.
  static Version? tryParse(String text) {
    var value = text.trim();
    if (value.startsWith('v') || value.startsWith('V')) {
      value = value.substring(1);
    }
    value = value.split(RegExp('[-+]')).first;

    final parts = value.split('.');
    if (parts.isEmpty || parts.length > 3) return null;

    final numbers = <int>[];
    for (final part in parts) {
      final number = int.tryParse(part);
      if (number == null || number < 0) return null;
      numbers.add(number);
    }

    return Version(
      numbers[0],
      numbers.length > 1 ? numbers[1] : 0,
      numbers.length > 2 ? numbers[2] : 0,
    );
  }

  final int major;
  final int minor;
  final int patch;

  @override
  int compareTo(Version other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  bool operator >(Version other) => compareTo(other) > 0;

  @override
  bool operator ==(Object other) =>
      other is Version &&
      major == other.major &&
      minor == other.minor &&
      patch == other.patch;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}

/// Whether [candidate] is a newer release than [current].
///
/// Unparseable input is never treated as newer: a malformed tag must not
/// trigger an update.
bool isNewer(String candidate, String current) {
  final next = Version.tryParse(candidate);
  final now = Version.tryParse(current);
  if (next == null || now == null) return false;
  return next > now;
}
