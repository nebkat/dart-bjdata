/// The revision of the BJData specification an encoder writes.
///
/// This is a ceiling on what may be emitted, for when the consumer is known to
/// predate a revision. Decoding ignores it and always accepts everything this
/// library understands.
enum BjdataVersion {
  /// Draft 3, frozen on 23 March 2025.
  ///
  /// Structure-of-Arrays containers are never written, whatever layout is
  /// requested, because a draft 3 reader cannot parse them. Everything else this
  /// library emits is byte-identical under both revisions, so this is currently
  /// the only difference between them.
  draft3,

  /// Draft 4, the current stable revision.
  ///
  /// Adds Structure-of-Arrays containers, which are written according to the
  /// configured layout. Also adds extension types (`E`), which this library does
  /// not implement and so never writes.
  draft4,
}
