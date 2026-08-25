/// The revision of the BJData specification an encoder writes.
///
/// This is a ceiling on what may be emitted, for when the consumer is known to
/// predate a revision. Decoding ignores it and always accepts everything this
/// library understands.
enum BjdataVersion {
  /// Draft 3, frozen at the `Draft-3` tag on 24 March 2025.
  ///
  /// Adds the `byte` type (`B`), and column-major storage for optimized
  /// N-dimensional arrays, whose dimension array is wrapped in a second `[`.
  ///
  /// https://github.com/NeuroJSON/bjdata/blob/Draft-3/Binary_JData_Specification.md
  draft3(3),

  /// Draft 4, frozen at the `Draft-4` tag on 9 April 2026, and the revision this
  /// library writes by default.
  ///
  /// Adds Structure-of-Arrays containers, along with the fixed-length, dictionary
  /// and offset-table storage their variable-length strings use, and extension
  /// types (`E`), which this library does not implement and so never writes.
  ///
  /// https://github.com/NeuroJSON/bjdata/blob/Draft-4/Binary_JData_Specification.md
  draft4(4);

  /// The draft number, as the specification counts revisions.
  final int value;

  const BjdataVersion(this.value);

  /// The revision numbered [v], or null if there is no such draft.
  static BjdataVersion? fromValueOrNull(int v) {
    for (final version in BjdataVersion.values) {
      if (version.value == v) return version;
    }
    return null;
  }

  /// The revision numbered [v], or throws a [FormatException] if there is no
  /// such draft.
  factory BjdataVersion.fromValue(int v) {
    final version = fromValueOrNull(v);
    if (version != null) return version;
    throw FormatException('Unknown BJData draft: $v');
  }
}
