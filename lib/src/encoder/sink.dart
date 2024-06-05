import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../error.dart';
import '../marker.dart';

/// Implements the chunked conversion from object to its BJData representation.
///
/// The sink only accepts one value, but will produce output in a chunked way.
class EncoderSink implements ChunkedConversionSink<Object?> {
  /// The byte sink receiving the encoded chunks.
  final ByteConversionSink _sink;
  final Object? Function(dynamic)? _toEncodable;
  final int _bufferSize;
  bool _isDone = false;

  EncoderSink(this._sink, this._toEncodable, this._bufferSize);

  /// Encodes the given object [o].
  ///
  /// It is an error to invoke this method more than once on any instance. While
  /// this makes the input effectively non-chunked the output will be generated
  /// in a chunked way.
  @override
  void add(Object? object) {
    if (_isDone) {
      throw StateError("Only one call to add allowed");
    }
    _isDone = true;
    ByteEncoder.encode(
      object,
      _toEncodable,
      _bufferSize,
      (chunk) => _sink.addSlice(chunk, 0, chunk.length, false),
    );
    _sink.close();
  }

  @override
  void close() {
    if (!_isDone) {
      _isDone = true;
      _sink.close();
    }
  }
}

// Implementation of encoder.dart/stringifier.

// ignore: avoid_dynamic_calls
dynamic _defaultToEncodable(dynamic object) => object.toJson();

/// BJData encoder that traverses an object structure and writes BJData source.
///
/// This is an abstract implementation that doesn't decide on the output
/// format, but writes the BJData through abstract methods like [writeString].
abstract class Encoder {
  /// List of objects currently being traversed. Used to detect cycles.
  final List _seen = [];

  /// Function called for each un-encodable object encountered.
  final Function(dynamic) _toEncodable;

  Encoder(dynamic Function(dynamic o)? toEncodable)
      : _toEncodable = toEncodable ?? _defaultToEncodable;

  String? get _partialResult;

  /// Check if an encountered object is already being traversed.
  ///
  /// Records the object if it isn't already seen. Should have a matching call to
  /// [_removeSeen] when the object is no longer being traversed.
  void _checkCycle(Object? object) {
    for (final s in _seen) {
      if (identical(object, s)) {
        throw BjdataCyclicError(object);
      }
    }
    _seen.add(object);
  }

  /// Remove [object] from the list of currently traversed objects.
  ///
  /// Should be called in the opposite order of the matching [_checkCycle]
  /// calls.
  void _removeSeen(Object? object) {
    assert(_seen.isNotEmpty);
    assert(identical(_seen.last, object));
    _seen.removeLast();
  }

  /// Append [Uint8List] directly to the BJData output.
  void writeBytes(Uint8List data);

  /// Append a byte to the BJData output.
  void writeByte(int byte);

  /// Append type marker
  void writeMarker(Marker tm) => writeByte(tm.value);

  /// Append a string contents to the BJDATA output.
  void writeStringContents(String string) => writeBytes(utf8.encode(string));

  /// Write an object.
  ///
  /// If [object] isn't directly encodable, the [_toEncodable] function gets one
  /// chance to return a replacement which is encodable.
  void writeObject(Object? object) {
    // Tries stringifying object directly. If it's not a simple value, List or
    // Map, call toBjdata() to get a custom representation and try serializing
    // that.
    if (writeBjdataValue(object)) return;
    _checkCycle(object);
    try {
      var customBjdata = _toEncodable(object);
      if (!writeBjdataValue(customBjdata)) {
        throw BjdataUnsupportedObjectError(object,
            partialResult: _partialResult);
      }
      _removeSeen(object);
    } catch (e) {
      throw BjdataUnsupportedObjectError(object,
          cause: e, partialResult: _partialResult);
    }
  }

  /// Serialize a [num], [String], [bool], [Null], [List] or [Map] value.
  ///
  /// Returns true if the value is one of these types, and false if not.
  /// If a value is both a [List] and a [Map], it's serialized as a [List].
  bool writeBjdataValue(Object? object) {
    if (object is int) {
      writeInt(object);
      return true;
    } else if (object is double) {
      writeDouble(object);
      return true;
    } else if (identical(object, true)) {
      writeMarker(Marker.true_);
      return true;
    } else if (identical(object, false)) {
      writeMarker(Marker.false_);
      return true;
    } else if (object == null) {
      writeMarker(Marker.null_);
      return true;
    } else if (object is Uint8List) {
      writeBuffer(object);
      return true;
    } else if (object is String) {
      writeString(object);
      return true;
    } else if (object is List) {
      _checkCycle(object);
      writeList(object);
      _removeSeen(object);
      return true;
    } else if (object is Map) {
      _checkCycle(object);
      // writeMap can fail if keys are not all strings.
      var success = writeMap(object);
      _removeSeen(object);
      return success;
    } else {
      return false;
    }
  }

  /// Append a [Uint8List] to the BJDATA output.
  void writeBuffer(Uint8List buffer) {
    writeMarker(Marker.arrayOpen);
    writeMarker(Marker.strongType);
    writeMarker(Marker.byte);
    writeMarker(Marker.count);
    writeInt(buffer.length);
    writeBytes(buffer);
  }

  /// Append a string to the BJDATA output.
  void writeString(String string) {
    writeMarker(Marker.string);
    writeStringWithoutMarker(string);
  }

  /// Append a string contents to the BJDATA output.
  void writeStringWithoutMarker(String string) {
    writeInt(string.length);
    writeStringContents(string);
  }

  /// Serialize an [int]
  void writeInt(int integer) {
    switch (integer) {
      case >= -128 && <= 127:
        writeMarker(Marker.int8);
        writeBytes(Uint8List.fromList([integer & 0xff]));
        return;
      case >= 0 && <= 255:
        writeMarker(Marker.uint8);
        writeBytes(Uint8List.fromList([integer & 0xff]));
        return;
      case >= -32768 && <= 32767:
        writeMarker(Marker.int16);
        writeBytes(Uint8List(2)
          ..buffer.asByteData().setInt16(0, integer, Endian.little));
        return;
      case >= 0 && <= 65535:
        writeMarker(Marker.uint16);
        writeBytes(Uint8List(2)
          ..buffer.asByteData().setUint16(0, integer, Endian.little));
        return;
      case >= -2147483648 && <= 2147483647:
        writeMarker(Marker.int32);
        writeBytes(Uint8List(4)
          ..buffer.asByteData().setInt32(0, integer, Endian.little));
        return;
      case >= 0 && <= 4294967295:
        writeMarker(Marker.uint32);
        writeBytes(Uint8List(4)
          ..buffer.asByteData().setUint32(0, integer, Endian.little));
        return;
      default:
        writeMarker(Marker.int64);
        writeBytes(Uint8List(8)
          ..buffer.asByteData().setInt64(0, integer, Endian.little));
    }
  }

  /// Serialize a [double]
  void writeDouble(double number) {
    writeMarker(Marker.float64);
    writeBytes((ByteData(8)..setFloat64(0, number, Endian.little))
        .buffer
        .asUint8List());
  }

  /// Serialize a [List].
  void writeList(List<Object?> list) {
    if (list.isEmpty) {
      writeMarker(Marker.arrayOpen);
      writeMarker(Marker.arrayClose);
      return;
    }
    writeMarker(Marker.arrayOpen);
    writeMarker(Marker.count);
    writeInt(list.length);
    for (final element in list) {
      writeObject(element);
    }
  }

  /// Serialize a [Map].
  bool writeMap(Map<Object?, Object?> map) {
    if (map.isEmpty) {
      writeMarker(Marker.objectOpen);
      writeMarker(Marker.objectClose);
      return true;
    }
    if (map.keys.any((key) => key is! String)) return false;
    writeMarker(Marker.objectOpen);
    writeMarker(Marker.count);
    writeInt(map.length);
    map.forEach((key, value) {
      writeStringWithoutMarker(key as String);
      writeObject(value);
    });
    return true;
  }
}

/// Specialization of [Encoder] that writes the BJDATA as UTF-8.
///
/// The BJData is written to [Uint8List] buffers.
/// The buffers are then passed back to a user provided callback method.
class ByteEncoder extends Encoder {
  final int bufferSize;
  final void Function(Uint8List list) addChunk;
  Uint8List buffer;
  int index = 0;

  int get free => buffer.length - index;

  ByteEncoder(super.toEncodable, this.bufferSize, this.addChunk)
      : buffer = Uint8List(bufferSize);

  /// Convert [object] to UTF-8 encoded BJDATA.
  ///
  /// Calls [addChunk] with slices of UTF-8 code units.
  /// These will typically have size [bufferSize], but may be shorter.
  /// The buffers are not reused, so the [addChunk] call may keep and reuse the
  /// chunks.
  static void encode(
    Object? object,
    dynamic Function(dynamic o)? toEncodable,
    int bufferSize,
    void Function(Uint8List chunk) addChunk,
  ) {
    final stringifier = ByteEncoder(toEncodable, bufferSize, addChunk);
    stringifier.writeObject(object);
    stringifier.flush(refill: false);
  }

  /// Must be called at the end to push the last chunk to the [addChunk]
  /// callback.
  void flush({bool refill = true}) {
    if (index > 0) {
      addChunk(Uint8List.sublistView(buffer, 0, index));
    }
    buffer = Uint8List(refill ? bufferSize : 0);
    index = 0;
  }

  @override
  String? get _partialResult => null;

  @override
  void writeBytes(Uint8List data) {
    int copied = 0;
    do {
      final remaining = data.length - copied;
      final copy = min(free, remaining);
      buffer.setRange(index, index + copy, data, copied);
      copied += copy;
      index += copy;
      if (index == buffer.length) flush();
    } while (copied < data.length);
  }

  @override
  void writeByte(int byte) {
    assert(byte <= 0xff);
    buffer[index++] = byte;
    if (index == buffer.length) flush();
  }
}
