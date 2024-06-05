enum Marker {
  /* Z */ null_(0x5A),
  /* T */ true_(0x54),
  /* F */ false_(0x46),
  /* N */ noop(0x4E),

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
  /* # */ count(0x23);

  final int value;

  const Marker(this.value);

  factory Marker.fromValue(int v) {
    for (final value in Marker.values) {
      if (value.value == v) return value;
    }
    throw FormatException(
        'Invalid BJData marker: 0x${v.toRadixString(16).padLeft(2, '0')}');
  }

  bool get isTypeMarker => index < Marker.arrayOpen.index;
  bool get isValidLengthTypeMarker =>
      index >= Marker.uint8.index && index <= Marker.int64.index;
  bool get isValidStrongType =>
      index >= Marker.uint8.index && index <= Marker.byte.index;
}
