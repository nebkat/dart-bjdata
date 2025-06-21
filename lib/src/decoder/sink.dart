import 'dart:convert';
import 'dart:math';
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

class Decoder {
  Decoder([this._reviver]);

  final Object? Function(Object? key, Object? value)? _reviver;
  int _offset = 0;
  late Uint8List _bytes;

  dynamic parse(List<int> input) {
    if (input is Uint8List) {
      _bytes = input;
    } else {
      _bytes = Uint8List.fromList(input);
    }
    final value = _readValue();
    if (_offset != _bytes.length) {
      throw FormatException('Trailing data at offset $_offset');
    }
    return _reviver == null ? value : _reviver!(null, value);
  }

  Uint8List _readUint8List(int length) {
    final view = Uint8List.sublistView(_bytes, _offset, _offset + length);
    _offset += length;
    return view;
  }

  ByteData _readByteData(int length) => ByteData.sublistView(_readUint8List(length));

  Marker _peekMarker() => Marker.fromValue(_bytes[_offset]);

  bool _peekMarkerConsumeIf(Marker marker) {
    if (_peekMarker() == marker) {
      _offset++;
      return true;
    }
    return false;
  }

  Marker _readMarker() => Marker.fromValue(_readUint8());
  Object? _readValue() => _readValueForMarker(_readMarker());

  Object? _readValueForMarker(Marker marker) {
    return switch (marker) {
      Marker.null_ => null,
      Marker.true_ => true,
      Marker.false_ => false,
      Marker.noop => null,
      Marker.uint8 => _readUint8(),
      Marker.int8 => _readInt8(),
      Marker.uint16 => _readUint16(),
      Marker.int16 => _readInt16(),
      Marker.uint32 => _readUint32(),
      Marker.int32 => _readInt32(),
      Marker.uint64 => _readUint64(),
      Marker.int64 => _readInt64(),
      Marker.float16 => _readFloat16(),
      Marker.float32 => _readFloat32(),
      Marker.float64 => _readFloat64(),
      Marker.char => _readChar(),
      Marker.byte => _readByte(),
      Marker.string => _readString(),
      Marker.huge => _readHuge(),
      Marker.arrayOpen => _readArray(),
      Marker.objectOpen => _readMap(),
      _ => throw FormatException('Unexpected non-value type marker: $marker'),
    };
  }

  int _readLength() {
    final marker = _readMarker();
    return switch (marker) {
      Marker.uint8 => _readUint8(),
      Marker.int8 => _readInt8(),
      Marker.uint16 => _readUint16(),
      Marker.int16 => _readInt16(),
      Marker.uint32 => _readUint32(),
      Marker.int32 => _readInt32(),
      Marker.uint64 => _readUint64(),
      Marker.int64 => _readInt64(),
      _ => throw FormatException('Unexpected non-length type marker: $marker'),
    };
  }

  int _readUint8() => _readByteData(1).getUint8(0);
  int _readInt8() => _readByteData(1).getInt8(0);
  int _readUint16() => _readByteData(2).getUint16(0, Endian.little);
  int _readInt16() => _readByteData(2).getInt16(0, Endian.little);
  int _readUint32() => _readByteData(4).getUint32(0, Endian.little);
  int _readInt32() => _readByteData(4).getInt32(0, Endian.little);
  int _readUint64() {
    if (1 is! double) {
      // Native
      return _readByteData(8).getUint64(0, Endian.little);
    } else {
      // Web
      return _readUint8List(8).reversed.fold(0, (acc, byte) => (acc *= 256) + byte);
    }
  }

  int _readInt64() {
    if (1 is! double) {
      // Native
      return _readByteData(8).getUint64(0, Endian.little);
    } else {
      // Web
      final b = _readUint8List(8);
      int v = b.reversed.fold(0, (acc, byte) => (acc *= 256) + byte);
      if (b[7] & 0x80 != 0) {
        v -= pow(2, 63).toInt();
      }
      return v;
    }
  }

  double _readFloat16() => throw UnsupportedError("Half-precision floats not supported"); // TODO
  double _readFloat32() => _readByteData(4).getFloat32(0, Endian.little);
  double _readFloat64() => _readByteData(8).getFloat64(0, Endian.little);

  int _readByte() => _readUint8();
  String _readChar() => String.fromCharCode(_readUint8());

  BigInt _readHuge() => _readUint8List(_readLength()).reversed.fold(
        BigInt.zero,
        (acc, byte) => (acc << 8) | BigInt.from(byte),
      );

  String _readString() => utf8.decode(_readUint8List(_readLength()));
  Uint8List? _readBuffer(int length) => _readUint8List(length);

  (Marker?, int?) _readStrongTypeAndCount() {
    Marker? strongType;
    int? count;

    if (_peekMarkerConsumeIf(Marker.strongType)) {
      // Read strong type
      strongType = _readMarker();
      if (!strongType.isValidStrongType) {
        throw FormatException('Invalid strong type: $strongType');
      }

      // Must be followed by count
      final countMarker = _readUint8();
      if (Marker.count.value == count) {
        throw FormatException(
            'Expected count marker to follow strong type: got 0x${countMarker.toRadixString(16).padLeft(2, '0')}');
      }

      // Read count
      count = _readLength();
    } else if (_peekMarkerConsumeIf(Marker.count)) {
      // Read count
      count = _readLength();
    }

    return (strongType, count);
  }

  List<Object?>? _readArray() {
    final (strongType, count) = _readStrongTypeAndCount();

    if (strongType == Marker.byte) {
      return _readBuffer(count!);
    }

    final list = <Object?>[];
    for (var i = 0; count != null ? i < count : true; i++) {
      if (count == null && _peekMarkerConsumeIf(Marker.arrayClose)) break;
      final value = _readValueForMarker(strongType ?? _readMarker());
      list.add(_reviver == null ? value : _reviver!(i, value));
    }
    return list;
  }

  Map<String, Object?>? _readMap() {
    final (strongType, count) = _readStrongTypeAndCount();

    final map = <String, Object?>{};
    for (var i = 0; count != null ? i < count : true; i++) {
      if (count == null && _peekMarker() == Marker.objectClose) break;
      final key = _readString();
      final value = _readValueForMarker(strongType ?? _readMarker());
      map[key] = _reviver == null ? value : _reviver!(key, value);
    }
    return map;
  }
}
