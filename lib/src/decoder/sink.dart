import 'dart:convert';
import 'dart:typed_data';

import '../marker.dart';

// /// Implements the chunked conversion from a UTF-8 encoding of JSON
// /// to its corresponding object.
// class DecoderSink implements Sink<List<int>> {
//   final Decoder _decoder;
//   final Sink<Object?> _sink;
//
//   DecoderSink(reviver, this._sink) : _decoder = _createDecoder(reviver);
//
//   static Decoder _createDecoder(
//     Object? Function(Object? key, Object? value)? reviver,
//   ) {
//     return Decoder(reviver);
//   }
//
//   @override
//   void add(List<int> chunk) {
//     _addChunk(chunk, 0, chunk.length);
//   }
//
//   @override
//   void close() {
//     _decoder.close();
//     var decoded = _decoder.result;
//     _sink.add(decoded);
//     _sink.close();
//   }
// }

class BjdataReader {
  BjdataReader([this._reviver]);

  final Object? Function(Object? key, Object? value)? _reviver;
  int _offset = 0;
  late ByteData _bytes;

  dynamic read(List<int> input) {
    if (input is TypedData) {
      _bytes = ByteData.sublistView(input as TypedData);
    } else {
      _bytes = ByteData.sublistView(Uint8List.fromList(input));
    }
    if (_bytes.lengthInBytes == 0) {
      throw FormatException('Empty input', _bytes, 0);
    }
    final value = _readValue();
    if (_offset != _bytes.lengthInBytes) {
      throw FormatException('Trailing data at offset $_offset', _bytes, _offset);
    }
    return _reviver == null ? value : _reviver!(null, value);
  }

  int _offsetIncrement(int count) {
    final oldOffset = _offset;
    _offset += count;
    if (_offset > _bytes.lengthInBytes) {
      throw FormatException("Unexpected end of input", _bytes, _bytes.lengthInBytes);
    }
    return oldOffset;
  }

  Uint8List _readUint8ListView(int length) {
    final view = Uint8List.sublistView(_bytes, _offset, _offset + length);
    _offset += length;
    return view;
  }

  ByteBuffer _readBufferCopy(int length) => _readUint8ListView(length).sublist(0).buffer;

  ByteBuffer _readBufferCopyCorrectedEndian(int count, int elementSize) {
    if (Endian.host == Endian.little) {
      return _readBufferCopy(count * elementSize);
    }

    final buffer = ByteData(count * elementSize);
    for (var i = 0; i < count; i++) {
      final _ = switch (elementSize) {
        2 => buffer.setUint16(i * elementSize, buffer.getUint16(i * elementSize, Endian.little), Endian.big),
        4 => buffer.setUint32(i * elementSize, buffer.getUint32(i * elementSize, Endian.little), Endian.big),
        8 => buffer.setUint64(i * elementSize, buffer.getUint64(i * elementSize, Endian.little), Endian.big),
        _ => throw ArgumentError.value(elementSize, 'elementSize', 'Must be 2, 4 or 8'),
      };
    }
    return buffer.buffer;
  }

  ByteData _readByteDataCopy(int length) => _readBufferCopy(length).asByteData();
  Uint8List _readUint8ListCopy(int length) => _readBufferCopy(length).asUint8List();
  Int8List _readInt8ListCopy(int length) => _readBufferCopy(length).asInt8List();
  Uint16List _readUint16ListCopy(int count) => _readBufferCopyCorrectedEndian(count, 2).asUint16List();
  Int16List _readInt16ListCopy(int count) => _readBufferCopyCorrectedEndian(count, 2).asInt16List();
  Uint32List _readUint32ListCopy(int count) => _readBufferCopyCorrectedEndian(count, 4).asUint32List();
  Int32List _readInt32ListCopy(int count) => _readBufferCopyCorrectedEndian(count, 4).asInt32List();
  Object _readUint64ListCopy(int count) {
    if (1 is! double) return _readBufferCopyCorrectedEndian(count, 8).asUint64List();

    // Web doesn't support Uint64List
    List<int> list = [];
    for (var i = 0; i < count; i++) {
      list.add(_readUint64());
    }
    return list;
  }

  Object _readInt64ListCopy(int count) {
    if (1 is! double) return _readBufferCopyCorrectedEndian(count, 8).asInt64List();

    // Web doesn't support Int64List
    List<int> list = [];
    for (var i = 0; i < count; i++) {
      list.add(_readInt64());
    }
    return list;
  }

  Float32List _readFloat16ListCopy(int count) {
    final list = Float32List(count);
    for (var i = 0; i < count; i++) {
      list[i] = _readFloat16();
    }
    return list;
  }

  Float32List _readFloat32ListCopy(int count) => _readBufferCopyCorrectedEndian(count, 4).asFloat32List();
  Float64List _readFloat64ListCopy(int count) => _readBufferCopyCorrectedEndian(count, 8).asFloat64List();

  int _peek() => _offset < _bytes.lengthInBytes
      ? _bytes.getUint8(_offset)
      : throw FormatException("Unexpected end of input", _bytes, _offset);

  BjdataMarker _peekMarker() {
    final v = _peek();
    final marker = BjdataMarker.fromValueOrNull(v);
    if (marker == null) {
      throw FormatException(
        'Invalid BJData marker: 0x${v.toRadixString(16).padLeft(2, '0')}',
        _bytes,
        _offset,
      );
    }
    return marker;
  }

  bool _peekMarkerConsumeIf(BjdataMarker marker) {
    if (_peekMarker() == marker) {
      _offset++;
      return true;
    }
    return false;
  }

  BjdataMarker _readMarker() {
    final marker = _peekMarker();
    _offset++;
    return marker;
  }

  Object? _readValue() => _readValueForMarker(_readMarker());

  Object? _readValueForMarker(BjdataMarker marker) {
    return switch (marker) {
      BjdataMarker.null_ => null,
      BjdataMarker.true_ => true,
      BjdataMarker.false_ => false,
      BjdataMarker.uint8 => _readUint8(),
      BjdataMarker.int8 => _readInt8(),
      BjdataMarker.uint16 => _readUint16(),
      BjdataMarker.int16 => _readInt16(),
      BjdataMarker.uint32 => _readUint32(),
      BjdataMarker.int32 => _readInt32(),
      BjdataMarker.uint64 => _readUint64(),
      BjdataMarker.int64 => _readInt64(),
      BjdataMarker.float16 => _readFloat16(),
      BjdataMarker.float32 => _readFloat32(),
      BjdataMarker.float64 => _readFloat64(),
      BjdataMarker.char => _readChar(),
      BjdataMarker.byte => _readByte(),
      BjdataMarker.string => _readString(),
      BjdataMarker.huge => _readHuge(),
      BjdataMarker.arrayOpen => _readArray(),
      BjdataMarker.objectOpen => _readMap(),
      _ => throw FormatException('Unexpected non-value type marker: $marker', _bytes, _offset - 1),
    };
  }

  int _readLength() {
    final offsetBefore = _offset;
    final marker = _readMarker();
    final length = switch (marker) {
      BjdataMarker.uint8 => _readUint8(),
      BjdataMarker.int8 => _readInt8(),
      BjdataMarker.uint16 => _readUint16(),
      BjdataMarker.int16 => _readInt16(),
      BjdataMarker.uint32 => _readUint32(),
      BjdataMarker.int32 => _readInt32(),
      BjdataMarker.uint64 => _readUint64(),
      BjdataMarker.int64 => _readInt64(),
      _ => throw FormatException('Unexpected non-length type marker: $marker', _bytes, offsetBefore),
    };
    if (length < 0) throw FormatException('Negative length: $length', _bytes, offsetBefore);
    return length;
  }

  int _readUint8() => _bytes.getUint8(_offsetIncrement(1));
  int _readInt8() => _bytes.getInt8(_offsetIncrement(1));
  int _readUint16() => _bytes.getUint16(_offsetIncrement(2), Endian.little);
  int _readInt16() => _bytes.getInt16(_offsetIncrement(2), Endian.little);
  int _readUint32() => _bytes.getUint32(_offsetIncrement(4), Endian.little);
  int _readInt32() => _bytes.getInt32(_offsetIncrement(4), Endian.little);
  int _readUint64() {
    if (1 is! double) {
      // Native
      return _bytes.getUint64(_offsetIncrement(8), Endian.little);
    } else {
      // Web
      final lo = _readUint32();
      final hi = _readUint32();
      return lo + hi * 4294967296;
    }
  }

  int _readInt64() {
    if (1 is! double) {
      // Native
      return _bytes.getInt64(_offsetIncrement(8), Endian.little);
    } else {
      // Web
      final lo = _readUint32().toUnsigned(32);
      final hi = _readUint32().toUnsigned(32);
      if (hi & 0x80000000 == 0) {
        return lo + hi * 4294967296;
      } else {
        // Two's complement inversion
        final tchi = ~hi & 0xFFFFFFFF;
        final tclo = ~lo & 0xFFFFFFFF;
        return -(tclo + tchi * 4294967296 + 1);
      }
    }
  }

  double _readFloat16() {
    final int f16 = _readUint16();

    final int sign = (f16 >> 15) & 0x1;
    final int exp = (f16 >> 10) & 0x1F;
    final int frac = f16 & 0x03FF;

    final f32 = switch (exp) {
      // Signed zero
      0 when frac == 0 => sign << 31,
      // Subnormal
      0 when frac != 0 => ((int frac) {
          int exp = 1;
          while ((frac & 0x0400) == 0) {
            frac <<= 1;
            exp -= 1;
          }
          frac &= 0x03FF;
          return (sign << 31) | ((exp + 112) << 23) | (frac << 13);
        })(frac),
      // Inf/NaN
      0x1F => sign << 31 | (0xFF << 23) | (frac << 13),
      // Normal
      _ => (sign << 31) | ((exp + 112) << 23) | (frac << 13),
    };

    return (ByteData(4)..setUint32(0, f32, Endian.little)).getFloat32(0, Endian.little);
  }

  double _readFloat32() => _bytes.getFloat32(_offsetIncrement(4), Endian.little);
  double _readFloat64() => _bytes.getFloat64(_offsetIncrement(8), Endian.little);

  int _readByte() => _readUint8();
  String _readChar() => String.fromCharCode(_readUint8());
  BigInt _readHuge() => BigInt.parse(_readString());
  String _readString() => utf8.decode(_readUint8ListView(_readLength()));

  (BjdataMarker?, int?) _readStrongTypeAndCount() {
    BjdataMarker? strongType;
    int? count;

    if (_peekMarkerConsumeIf(BjdataMarker.strongType)) {
      // Read strong type
      strongType = _readMarker();
      if (!strongType.isValidStrongType) {
        throw FormatException('Invalid strong type: $strongType', _bytes, _offset - 1);
      }

      // Must be followed by count
      final countMarker = _readUint8();
      if (countMarker != BjdataMarker.count.value) {
        throw FormatException(
          'Expected count marker to follow strong type: '
          'got 0x${countMarker.toRadixString(16).padLeft(2, '0')} / ${BjdataMarker.fromValueOrNull(countMarker)}',
          _bytes,
          _offset - 1,
        );
      }

      // Read count
      count = _readLength();
    } else if (_peekMarkerConsumeIf(BjdataMarker.count)) {
      // Read count
      count = _readLength();
    }

    return (strongType, count);
  }

  Object _readArray() {
    final offsetBefore = _offset - 1;
    final (strongType, count) = _readStrongTypeAndCount();

    if (strongType != null && strongType.isValidStrongType && strongType != BjdataMarker.char) {
      return switch (strongType) {
        BjdataMarker.byte => _readByteDataCopy(count!),
        BjdataMarker.uint8 => _readUint8ListCopy(count!),
        BjdataMarker.int8 => _readInt8ListCopy(count!),
        BjdataMarker.uint16 => _readUint16ListCopy(count!),
        BjdataMarker.int16 => _readInt16ListCopy(count!),
        BjdataMarker.uint32 => _readUint32ListCopy(count!),
        BjdataMarker.int32 => _readInt32ListCopy(count!),
        BjdataMarker.uint64 => _readUint64ListCopy(count!),
        BjdataMarker.int64 => _readInt64ListCopy(count!),
        BjdataMarker.float16 => _readFloat16ListCopy(count!),
        BjdataMarker.float32 => _readFloat32ListCopy(count!),
        BjdataMarker.float64 => _readFloat64ListCopy(count!),
        _ => throw FormatException('Invalid strong type: $strongType', _bytes, offsetBefore),
      };
    }

    final list = <Object?>[];
    for (var i = 0; count != null ? i < count : true; i++) {
      while (strongType == null && _peekMarkerConsumeIf(BjdataMarker.noop)) {}
      if (count == null && _peekMarkerConsumeIf(BjdataMarker.arrayClose)) break;
      final value = _readValueForMarker(strongType ?? _readMarker());
      list.add(_reviver == null ? value : _reviver!(i, value));
    }
    return list;
  }

  Map<String, Object?>? _readMap() {
    final (strongType, count) = _readStrongTypeAndCount();

    final map = <String, Object?>{};
    for (var i = 0; count != null ? i < count : true; i++) {
      while (_peekMarkerConsumeIf(BjdataMarker.noop)) {}
      if (count == null && _peekMarkerConsumeIf(BjdataMarker.objectClose)) break;
      final key = _readString();
      final value = _readValueForMarker(strongType ?? _readMarker());
      map[key] = _reviver == null ? value : _reviver!(key, value);
    }
    return map;
  }
}
