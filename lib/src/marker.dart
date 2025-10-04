/// BJData markers
///
/// Used to denote types and structure in the BJData binary format.
///
/// [null_] through [huge] are considered values.
/// [arrayOpen] and [objectOpen] are containers.
/// [strongType], [count], and [noop] are container modifiers.
enum BjdataMarker {
  /* Z */ null_(0x5A),
  /* T */ true_(0x54),
  /* F */ false_(0x46),

  /* U */ uint8(0x55),
  /* i */ int8(0x69),
  /* u */ uint16(0x75),
  /* I */ int16(0x49),
  /* m */ uint32(0x6D),
  /* l */ int32(0x6C),
  /* M */ uint64(0x4D),
  /* L */ int64(0x4C),
  /* h */ float16(0x68),
  /* d */ float32(0x64),
  /* D */ float64(0x44),
  /* C */ char(0x43),
  /* B */ byte(0x42),

  /* S */ string(0x53),
  /* H */ huge(0x48),

  /* [ */ arrayOpen(0x5B),
  /* { */ objectOpen(0x7B),

  /* ] */ arrayClose(0x5D),
  /* } */ objectClose(0x7D),

  /* $ */ strongType(0x24),
  /* # */ count(0x23),
  /* N */ noop(0x4E);

  final int value;

  const BjdataMarker(this.value);

  int get i => value;
  String get ascii => String.fromCharCode(value);

  /// The marker corresponding to the binary value [v], or null if [v] is not a valid marker.
  static BjdataMarker? fromValueOrNull(int v) {
    for (final value in BjdataMarker.values) {
      if (value.value == v) return value;
    }
    return null;
  }

  /// The marker corresponding to the binary value [v], or throws a [FormatException] if [v] is not a valid marker.
  factory BjdataMarker.fromValue(int v) {
    final marker = fromValueOrNull(v);
    if (marker != null) return marker;
    throw FormatException(
      'Invalid BJData marker: 0x${v.toRadixString(16).padLeft(2, '0')}',
    );
  }

  /// Whether this marker represents a value (not a container or modifier).
  bool get isValueMarker => index < BjdataMarker.arrayOpen.index;

  /// Whether this marker is a valid length type (for strings, container count, etc).
  bool get isValidLengthMarker => index >= BjdataMarker.uint8.index && index <= BjdataMarker.int64.index;

  /// Whether this marker is a valid strong type (for typed containers).
  bool get isValidStrongType => index >= BjdataMarker.uint8.index && index <= BjdataMarker.byte.index;
}
