import 'dart:typed_data';

import 'marker.dart';

/// The IEEE 754 half-precision bit pattern of [value], rounded to nearest even.
int bjdataFloat16Bits(double value) {
  final data = ByteData(4)..setFloat32(0, value, Endian.little);
  var bits = data.getUint32(0, Endian.little);
  final sign = (bits & 0x80000000) >> 16;
  bits &= 0x7FFFFFFF;

  // Inf, NaN or a magnitude too large for float16.
  if (bits >= 0x47800000) return sign | (bits > 0x7F800000 ? 0x7E00 : 0x7C00);

  // Normal float16.
  if (bits >= 0x38800000) {
    final mantissaOdd = (bits >> 13) & 1;
    return sign | ((bits - 0x38000000 + 0xFFF + mantissaOdd) >> 13);
  }

  // Subnormal float16, or an underflow to signed zero. A float32 that is itself
  // subnormal (a zero exponent field) is far below the float16 subnormal range.
  final exponent = bits >> 23;
  if (exponent == 0) return sign;
  return sign | _shiftRoundToNearestEven(0x800000 | (bits & 0x7FFFFF), 126 - exponent);
}

/// `value >> shift`, rounded to nearest with ties going to the even value.
int _shiftRoundToNearestEven(int value, int shift) {
  if (shift > 24) return 0;
  final quotient = value >> shift;
  final remainder = value & ((1 << shift) - 1);
  final half = 1 << (shift - 1);
  if (remainder > half || (remainder == half && quotient.isOdd)) return quotient + 1;
  return quotient;
}

/// The value of the IEEE 754 half-precision bit pattern [bits].
double bjdataFloat16ToDouble(int bits) {
  final sign = (bits >> 15) & 0x1;
  final exponent = (bits >> 10) & 0x1F;
  final fraction = bits & 0x03FF;

  final f32 = switch (exponent) {
    0 when fraction == 0 => sign << 31, // Signed zero
    0 => ((int fraction) {
        var exponent = 1;
        while ((fraction & 0x0400) == 0) {
          fraction <<= 1;
          exponent -= 1;
        }
        fraction &= 0x03FF;
        return (sign << 31) | ((exponent + 112) << 23) | (fraction << 13);
      })(fraction), // Subnormal
    0x1F => sign << 31 | (0xFF << 23) | (fraction << 13), // Inf or NaN
    _ => (sign << 31) | ((exponent + 112) << 23) | (fraction << 13),
  };

  return (ByteData(4)..setUint32(0, f32, Endian.little)).getFloat32(0, Endian.little);
}

/// Whether [value] survives a trip through float32 unchanged.
bool bjdataFitsFloat32(double value) => value.isNaN || (Float32List(1)..[0] = value)[0] == value;

/// Whether [value] survives a trip through float16 unchanged.
bool bjdataFitsFloat16(double value) => value.isNaN || bjdataFloat16ToDouble(bjdataFloat16Bits(value)) == value;

/// The narrowest integer marker that holds every value between [min] and [max],
/// favouring unsigned types as the rest of the encoder does.
BjdataMarker bjdataIntegerMarker(int min, int max) => switch ((min, max)) {
      (>= 0, <= 255) => BjdataMarker.uint8,
      (>= -128, <= 127) => BjdataMarker.int8,
      (>= 0, <= 65535) => BjdataMarker.uint16,
      (>= -32768, <= 32767) => BjdataMarker.int16,
      (>= 0, <= 4294967295) => BjdataMarker.uint32,
      (>= -2147483648, <= 2147483647) => BjdataMarker.int32,
      (>= 0, _) => BjdataMarker.uint64,
      _ => BjdataMarker.int64,
    };

/// The narrowest float marker that holds [values] with no change to any of them.
BjdataMarker bjdataFloatMarker(Iterable<double> values) {
  if (values.every(bjdataFitsFloat16)) return BjdataMarker.float16;
  if (values.every(bjdataFitsFloat32)) return BjdataMarker.float32;
  return BjdataMarker.float64;
}

/// The number of bytes a single value costs in a generic array, including its
/// own type marker.
int _genericValueSize(Object? value) => switch (value) {
      int v => 1 + bjdataIntegerMarker(v, v).fixedByteLength!,
      double v => 1 + bjdataFloatMarker([v]).fixedByteLength!,
      _ => throw ArgumentError.value(value, 'value', 'Not a number'),
    };

/// How a uniform list of numbers is best written.
class BjdataNumericPacking {
  BjdataNumericPacking(this.marker, this.values);

  /// The strong type every value is written as.
  final BjdataMarker marker;

  /// The values, all [int] when [marker] is an integer type and all [double]
  /// when it is a float type.
  final List<Object?> values;
}

/// Describes [values] as a strongly-typed array, or returns null if they are not
/// all numbers of one kind or if a generic array would be smaller.
///
/// A generic array gives every value its own marker and so stores each at its
/// own width, while a strongly-typed array must be wide enough for the largest
/// value and pays that width throughout. Which wins depends entirely on the
/// spread of the values, so both are measured.
BjdataNumericPacking? tryBjdataNumericPacking(List<Object?> values) {
  if (values.isEmpty) return null;

  final BjdataMarker marker;
  if (values.every((v) => v is int)) {
    var min = values.first as int;
    var max = min;
    for (final value in values.cast<int>()) {
      if (value < min) min = value;
      if (value > max) max = value;
    }
    marker = bjdataIntegerMarker(min, max);
  } else if (values.every((v) => v is double)) {
    marker = bjdataFloatMarker(values.cast<double>());
  } else {
    return null;
  }

  // '[' '$' type '#', then the count, then the payload.
  final count = values.length;
  final packed = 4 + (1 + bjdataIntegerMarker(count, count).fixedByteLength!) + count * marker.fixedByteLength!;
  // '[' ... ']', each value carrying its own marker.
  var generic = 2;
  for (final value in values) {
    generic += _genericValueSize(value);
  }

  return packed < generic ? BjdataNumericPacking(marker, values) : null;
}
