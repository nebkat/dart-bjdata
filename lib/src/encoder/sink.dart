import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../error.dart';
import '../marker.dart';

/// Implements the chunked conversion from object to its BJData representation.
///
/// The sink only accepts one value, but will produce output in a chunked way.
class BjdataEncoderSink implements ChunkedConversionSink<Object?> {
  /// The byte sink receiving the encoded chunks.
  final ByteConversionSink _sink;
  final Object? Function(dynamic)? _toEncodable;
  final int _bufferSize;
  bool _isDone = false;

  BjdataEncoderSink(this._sink, this._toEncodable, this._bufferSize);

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
    BjdataBufferWriter.encode(
        object, _toEncodable, _bufferSize, (chunk) => _sink.addSlice(chunk, 0, chunk.length, false));
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

/// Implements the chunked conversion from object to its BJData representation.
///
/// The sink only accepts one value, but will produce output in a chunked way.
class BjdataBlockNotationEncoderSink implements ChunkedConversionSink<Object?> {
  final String? _indent;
  final Object? Function(dynamic)? _toEncodable;
  final StringConversionSink _sink;
  bool _isDone = false;

  BjdataBlockNotationEncoderSink(this._sink, this._toEncodable, this._indent);

  /// Encodes the given object [o].
  ///
  /// It is an error to invoke this method more than once on any instance. While
  /// this makes the input effectively non-chunked the output will be generated
  /// in a chunked way.
  @override
  void add(Object? o) {
    if (_isDone) {
      throw StateError("Only one call to add allowed");
    }
    _isDone = true;
    final stringSink = _sink.asStringSink();
    BjdataBlockNotationStringifier.printOn(o, stringSink, _toEncodable, _indent);
    stringSink.close();
  }

  @override
  void close() {
    /* do nothing */
  }
}

// Implementation of encoder.dart/stringifier.

// ignore: avoid_dynamic_calls
dynamic _defaultToEncodable(dynamic object) => object.toJson();

/// BJData writer that traverses an object structure and writes BJData source.
///
/// This is an abstract implementation that doesn't decide on the output
/// format, but writes the BJData through abstract methods like [writeString].
abstract class _BjdataWriter<T> {
  /// List of objects currently being traversed. Used to detect cycles.
  final List _seen = [];

  /// Function called for each un-encodable object encountered.
  final Function(dynamic) _toEncodable;

  _BjdataWriter(dynamic Function(dynamic o)? toEncodable) : _toEncodable = toEncodable ?? _defaultToEncodable;

  T? get _partialResult;

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

  /// Write an object.
  ///
  /// If [object] isn't directly encodable, the [_toEncodable] function gets one
  /// chance to return a replacement which is encodable.
  void write(Object? object) {
    // Tries encoding object directly. If it's not a simple value, List or
    // Map, call toJson() to get a custom representation and try serializing
    // that.
    if (writeValue(object)) return;
    _checkCycle(object);
    try {
      var customBjdata = _toEncodable(object);
      if (!writeValue(customBjdata)) {
        throw BjdataUnsupportedObjectError(object, partialResult: _partialResult);
      }
      _removeSeen(object);
    } on BjdataUnsupportedObjectError catch (_) {
      rethrow;
    } catch (e) {
      throw BjdataUnsupportedObjectError(object, cause: e, partialResult: _partialResult);
    }
  }

  /// Write a [num], [String], [bool], [Null], [List] or [Map] value.
  ///
  /// Returns true if the value is one of these types, and false if not.
  /// If a value is both a [List] and a [Map], it's serialized as a [List].
  bool writeValue(Object? object) {
    switch (object) {
      case int i
          // double.infinity is an int on web
          when (1 is! double || (i != double.infinity && i != double.negativeInfinity)):
        writeInt(i);
      case double d:
        writeDouble(d);
      case bool b when b == true:
        writeMarker(BjdataMarker.true_);
      case bool b when b == false:
        writeMarker(BjdataMarker.false_);
      case null:
        writeMarker(BjdataMarker.null_);
      case String s:
        writeString(s);
      case BigInt bi:
        writeBigInt(bi);
      case TypedData td:
        writeTypedData(td);
      case List l:
        _checkCycle(l);
        writeList(object);
        _removeSeen(object);
      case Map m:
        _checkCycle(m);
        // writeMap can fail if keys are not all strings.
        final success = writeMap(object);
        _removeSeen(object);
        return success;
      default:
        return false;
    }
    return true;
  }

  /// Append a string to the BJData output.
  void writeString(String string) {
    writeMarker(BjdataMarker.string);
    writeStringWithoutMarker(string);
  }

  /// Append a string contents to the BJData output.
  void writeStringWithoutMarker(String string) {
    writeInt(string.length);
    writeStringContents(string);
  }

  /// Serialize an [int]
  void writeInt(int integer) {
    final marker = switch (integer) {
      >= 0 && <= 255 => BjdataMarker.uint8,
      >= -128 && <= 127 => BjdataMarker.int8,
      >= 0 && <= 65535 => BjdataMarker.uint16,
      >= -32768 && <= 32767 => BjdataMarker.int16,
      >= 0 && <= 4294967295 => BjdataMarker.uint32,
      >= -2147483648 && <= 2147483647 => BjdataMarker.int32,
      >= 0 => BjdataMarker.uint64,
      _ => BjdataMarker.int64,
    };
    writeMarker(marker);
    writeIntWithoutMarker(marker, integer);
  }

  /// Serialize a [BigInt]
  void writeBigInt(BigInt bigInt) {
    writeMarker(BjdataMarker.huge);
    writeStringWithoutMarker(bigInt.toRadixString(10));
  }

  /// Serialize a [double]
  void writeDouble(double number) {
    writeMarker(BjdataMarker.float64);
    writeDoubleWithoutMarker(number);
  }

  /// Serialize a [List].
  void writeList(List<Object?> list) {
    writeMarker(BjdataMarker.arrayOpen);
    writeListContents(false, list);
    writeMarker(BjdataMarker.arrayClose);
  }

  /// Serialize a [Map].
  bool writeMap(Map<Object?, Object?> map) {
    if (map.keys.any((key) => key is! String)) return false;
    writeMarker(BjdataMarker.objectOpen);
    writeMapContents(false, map);
    writeMarker(BjdataMarker.objectClose);
    return true;
  }

  /// Serialize a [TypedData] buffer
  void writeTypedData(TypedData buffer) {
    final lengthInBytes = buffer.lengthInBytes;
    final elementSize = buffer.elementSizeInBytes;
    final elementCount = lengthInBytes ~/ elementSize;
    writeMarker(BjdataMarker.arrayOpen);
    writeMarker(BjdataMarker.strongType);
    final marker = switch (buffer) {
      Int8List() => BjdataMarker.int8,
      Uint8List() => BjdataMarker.uint8,
      Int16List() => BjdataMarker.int16,
      Uint16List() => BjdataMarker.uint16,
      Int32List() => BjdataMarker.int32,
      Uint32List() => BjdataMarker.uint32,
      Int64List() => BjdataMarker.int64,
      Uint64List() => BjdataMarker.uint64,
      Float32List() => BjdataMarker.float32,
      Float64List() => BjdataMarker.float64,
      ByteData() => BjdataMarker.byte,
      _ => throw ArgumentError.value(buffer, 'buffer', 'Not a typed buffer'),
    };
    writeMarker(marker);
    writeMarker(BjdataMarker.count);
    writeInt(elementCount);

    writeTypedDataContents(buffer);
  }

  /// Append type marker
  void writeMarker(BjdataMarker tm);

  /// Serialize an [int]
  void writeIntWithoutMarker(BjdataMarker marker, int integer);

  /// Serialize a [double]
  void writeDoubleWithoutMarker(double number);

  /// Append a string contents to the BJData output.
  void writeStringContents(String string);

  /// Serialize a [List]
  void writeListContents(bool hasCount, List<Object?> list) {
    for (final element in list) {
      write(element);
    }
  }

  /// Serialize a [Map]
  void writeMapContents(bool hasCount, Map<Object?, Object?> map) {
    for (final entry in map.entries) {
      writeStringWithoutMarker(entry.key as String);
      write(entry.value);
    }
  }

  /// Serialize a [TypedData] buffer
  void writeTypedDataContents(TypedData buffer);
}

/// Specialization of [_BjdataWriter] that writes the BJData to a buffer.
///
/// The BJData is written to [Uint8List] buffers.
/// The buffers are then passed back to a user provided callback method.
class BjdataBufferWriter extends _BjdataWriter {
  final int bufferSize;
  final void Function(Uint8List list) addChunk;
  Uint8List buffer;
  int index = 0;

  int get free => buffer.length - index;

  BjdataBufferWriter(super.toEncodable, this.bufferSize, this.addChunk) : buffer = Uint8List(bufferSize);

  /// Convert [object] to UTF-8 encoded BJData.
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
    final encoder = BjdataBufferWriter(toEncodable, bufferSize, addChunk);
    encoder.write(object);
    encoder.flush(refill: false);
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
  List<int>? get _partialResult => null;

  /// Append [Uint8List] directly to the BJData output.
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

  /// Append a byte to the BJData output.
  void writeByte(int byte) {
    assert(byte <= 0xff);
    buffer[index++] = byte;
    if (index == buffer.length) flush();
  }

  @override
  void writeMarker(BjdataMarker tm) => writeByte(tm.value);

  @override
  void writeStringContents(String string) => writeBytes(utf8.encode(string));

  @override
  void writeIntWithoutMarker(BjdataMarker marker, int integer) {
    writeBytes(switch (marker) {
      BjdataMarker.int8 => Uint8List.fromList([integer & 0xff]),
      BjdataMarker.uint8 => Uint8List.fromList([integer & 0xff]),
      BjdataMarker.int16 => Uint8List(2)..buffer.asByteData().setInt16(0, integer, Endian.little),
      BjdataMarker.uint16 => Uint8List(2)..buffer.asByteData().setUint16(0, integer, Endian.little),
      BjdataMarker.int32 => Uint8List(4)..buffer.asByteData().setInt32(0, integer, Endian.little),
      BjdataMarker.uint32 => Uint8List(4)..buffer.asByteData().setUint32(0, integer, Endian.little),
      BjdataMarker.int64 when 1 is! double => Uint8List(8)..buffer.asByteData().setInt64(0, integer, Endian.little),
      BjdataMarker.uint64 when 1 is! double => Uint8List(8)..buffer.asByteData().setUint64(0, integer, Endian.little),
      BjdataMarker.int64 || BjdataMarker.uint64 => (Uint8List(8)
        ..buffer.asByteData().setUint32(0, integer & 0xFFFFFFFF, Endian.little)
        ..buffer.asByteData().setUint32(4, (integer / 4294967296).floor(), Endian.little)),
      _ => throw ArgumentError.value(marker, 'marker', 'Not a valid int marker'),
    });
  }

  @override
  void writeDoubleWithoutMarker(double number) {
    writeBytes((ByteData(8)..setFloat64(0, number, Endian.little)).buffer.asUint8List());
  }

  @override
  void writeTypedDataContents(TypedData buffer) {
    final lengthInBytes = buffer.lengthInBytes;
    final elementSize = buffer.elementSizeInBytes;
    final elementCount = lengthInBytes ~/ elementSize;

    if (Endian.host == Endian.little || elementSize == 1) {
      writeBytes(Uint8List.sublistView(buffer));
    } else {
      final bytes = ByteData.sublistView(buffer);
      final copy = ByteData(lengthInBytes);
      for (var i = 0; i < elementCount; i++) {
        final _ = switch (elementSize) {
          2 => copy.setUint16(i * elementSize, bytes.getUint16(i * elementSize, Endian.little), Endian.big),
          4 => copy.setUint32(i * elementSize, bytes.getUint32(i * elementSize, Endian.little), Endian.big),
          8 => copy.setUint64(i * elementSize, bytes.getUint64(i * elementSize, Endian.little), Endian.big),
          _ => throw ArgumentError.value(elementSize, 'elementSizeInBytes', 'Must be 2, 4 or 8'),
        };
      }
      writeBytes(Uint8List.sublistView(copy));
    }
  }
}

class BjdataBlockNotationStringifier extends _BjdataWriter {
  final StringSink _sink;
  final String? _indent;
  int _indentLevel = 0;

  BjdataBlockNotationStringifier(
    this._sink,
    dynamic Function(dynamic o)? toEncodable,
    this._indent,
  ) : super(toEncodable);

  /// Convert object to a string.
  ///
  /// The [toEncodable] function is used to convert non-encodable objects
  /// to encodable ones.
  ///
  /// If [indent] is not `null`, the resulting JSON will be "pretty-printed"
  /// with newlines and indentation. The `indent` string is added as indentation
  /// for each indentation level. It should only contain valid JSON whitespace
  /// characters (space, tab, carriage return or line feed).
  static String stringify(
    Object? object,
    dynamic Function(dynamic object)? toEncodable,
    String? indent,
  ) {
    var output = StringBuffer();
    printOn(object, output, toEncodable, indent);
    return output.toString();
  }

  /// Convert object to a string, and write the result to the [output] sink.
  ///
  /// The result is written piecemally to the sink.
  static void printOn(
    Object? object,
    StringSink output,
    dynamic Function(dynamic o)? toEncodable,
    String? indent,
  ) {
    BjdataBlockNotationStringifier(output, toEncodable, indent).write(object);
    if (indent != null) output.write('\n');
  }

  @override
  String? get _partialResult => _sink is StringBuffer ? _sink.toString() : null;

  /// Add a new line if [_indent] is not `null`.
  void writeNewLine() {
    if (_indent == null) return;
    _sink.write('\n');
  }

  /// Add [count] indentations to the BJData block notation output.
  void writeIndentation(int count) {
    if (_indent == null) return;
    _sink.write(_indent! * count);
  }

  /// Add a block notation element to the BJData output.
  void writeBlock(String block) => _sink
    ..write('[')
    ..write(block)
    ..write(']');

  @override
  void writeMarker(BjdataMarker tm) => writeBlock(tm.ascii);

  @override
  void writeDoubleWithoutMarker(double number) => writeBlock(number.toString());

  @override
  void writeIntWithoutMarker(BjdataMarker marker, int integer) => writeBlock(integer.toString());

  @override
  void writeStringContents(String string) => writeBlock(string);

  @override
  void writeListContents(bool hasCount, List<Object?> list) {
    _indentLevel++;
    for (final element in list) {
      writeNewLine();
      writeIndentation(_indentLevel);
      write(element);
    }
    _indentLevel--;
    if (!hasCount) writeNewLine();
    if (!hasCount) writeIndentation(_indentLevel);
  }

  @override
  void writeMapContents(bool hasCount, Map<Object?, Object?> map) {
    _indentLevel++;
    for (final entry in map.entries) {
      writeNewLine();
      writeIndentation(_indentLevel);
      writeStringWithoutMarker(entry.key as String);
      write(entry.value);
    }
    _indentLevel--;
    if (!hasCount) writeNewLine();
    if (!hasCount) writeIndentation(_indentLevel);
  }

  @override
  void writeTypedDataContents(TypedData buffer) {
    writeNewLine();
    writeIndentation(_indentLevel + 1);
    if (buffer is ByteData) buffer = Uint8List.sublistView(buffer);
    for (final v in buffer as dynamic) {
      writeBlock(v.toString());
    }
  }
}
