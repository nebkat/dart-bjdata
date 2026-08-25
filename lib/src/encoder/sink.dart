import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../error.dart';
import '../marker.dart';
import '../nd.dart';
import '../config.dart';
import '../soa.dart';

/// Implements the chunked conversion from object to its BJData representation.
///
/// The sink only accepts one value, but will produce output in a chunked way.
class BjdataEncoderSink implements ChunkedConversionSink<Object?> {
  /// The byte sink receiving the encoded chunks.
  final ByteConversionSink _sink;
  final Object? Function(dynamic)? _toEncodable;
  final int _bufferSize;
  final BjdataConfig _config;
  bool _isDone = false;

  BjdataEncoderSink(this._sink, this._toEncodable, this._bufferSize, {BjdataConfig config = const BjdataConfig()})
      : _config = config;

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
        object, _toEncodable, _bufferSize, (chunk) => _sink.addSlice(chunk, 0, chunk.length, false),
        config: _config);
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
  final BjdataConfig _config;
  bool _isDone = false;

  BjdataBlockNotationEncoderSink(this._sink, this._toEncodable, this._indent,
      {BjdataConfig config = const BjdataConfig()})
      : _config = config;

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
    BjdataBlockNotationStringifier.printOn(o, stringSink, _toEncodable, _indent, config: _config);
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

  /// How the output is written.
  final BjdataConfig _config;

  _BjdataWriter(dynamic Function(dynamic o)? toEncodable, this._config)
      : _toEncodable = toEncodable ?? _defaultToEncodable;

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
        final layout = _config.effectiveSoa;
        final soa =
            layout == BjdataSoaLayout.off ? null : tryBjdataSoaCandidate(l, multiDimensional: _config.multiDimensional);
        final nd = soa == null && _config.multiDimensional ? tryBjdataNdCandidate(l) : null;
        if (soa != null) {
          writeSoa(soa, layout);
        } else if (nd != null) {
          writeNdArray(nd);
        } else {
          writeList(l);
        }
        _removeSeen(l);
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
  ///
  /// The length prefix counts UTF-8 bytes, which differs from `string.length`
  /// for any string outside the ASCII range.
  void writeStringWithoutMarker(String string) {
    writeInt(utf8.encode(string).length);
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

  /// Serialize a [double] as a `float64` without a type marker.
  void writeDoubleWithoutMarker(double number) => writeFloatWithoutMarker(BjdataMarker.float64, number);

  /// Serialize an [int] with a type marker.
  ///
  /// If [marker] is null, the smallest marker that fits [integer] is used.
  void writeIntWithMarker(BjdataMarker? marker, int integer) {
    if (marker == null) return writeInt(integer);
    writeMarker(marker);
    writeIntWithoutMarker(marker, integer);
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

  /// Serialize a [double] as [marker], which must be `h`, `d` or `D`.
  void writeFloatWithoutMarker(BjdataMarker marker, double number);

  /// Append [count] null padding bytes to the BJData output.
  void writePadding(int count);

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

  /// Serialize a rectangular nesting of typed rows as one N-dimensional array.
  ///
  /// The rows are written end to end in row-major order behind a dimension array
  /// count, so the result holds the same values as the nesting it replaces while
  /// carrying one container header rather than one per row.
  void writeNdArray(BjdataNdCandidate nd) {
    writeMarker(BjdataMarker.arrayOpen);
    writeMarker(BjdataMarker.strongType);
    writeMarker(nd.marker);
    writeMarker(BjdataMarker.count);
    writeMarker(BjdataMarker.arrayOpen);
    for (final dimension in nd.dimensions) {
      writeInt(dimension);
    }
    writeMarker(BjdataMarker.arrayClose);

    for (final row in nd.rows) {
      writeTypedDataContents(row);
    }
  }

  /// Begins a nested output block. Only meaningful for block notation output.
  void enterBlock() {}

  /// Ends a nested output block. Only meaningful for block notation output.
  void exitBlock() {}

  /// Starts a new line at the current block level. Only meaningful for block
  /// notation output.
  void newLine() {}

  /// Serialize a detected table as a Structure-of-Arrays container.
  ///
  /// Both layouts share the same schema, count and payload size; only the order
  /// of the payload differs. Offset tables always follow the payload in schema
  /// field order, whichever layout is used.
  void writeSoa(BjdataSoaCandidate soa, BjdataSoaLayout layout) {
    final columnMajor = layout == BjdataSoaLayout.columnMajor;
    writeMarker(columnMajor ? BjdataMarker.objectOpen : BjdataMarker.arrayOpen);
    writeSoaHeader(soa.schema, soa.dimensions);

    final offsets = {
      for (final field in soa.schema.offsetFields.entries) field.key: _SoaOffsetWriter(field.value),
    };
    enterBlock();
    if (columnMajor) {
      for (final field in soa.schema.fields.entries) {
        newLine();
        for (final record in soa.records) {
          writeSoaField(field.value, field.key, field.key, _soaRecordValue(record, field.key), offsets);
        }
      }
    } else {
      for (final record in soa.records) {
        newLine();
        for (final field in soa.schema.fields.entries) {
          writeSoaField(field.value, field.key, field.key, _soaRecordValue(record, field.key), offsets);
        }
      }
    }
    writeSoaOffsetTables(offsets);
    exitBlock();
  }

  static Object? _soaRecordValue(Map<String, Object?> record, String name) => record.containsKey(name)
      ? record[name]
      : throw ArgumentError.value(record, 'record', "Missing field '$name' declared by the schema");

  /// Serialize the `${schema}#count` header shared by both SoA layouts, with the
  /// container marker already written.
  void writeSoaHeader(BjdataSoaSchema schema, List<int> dimensions) {
    writeMarker(BjdataMarker.strongType);
    writeSoaFields(schema.fields);
    writeMarker(BjdataMarker.count);
    if (dimensions.length == 1) {
      writeInt(dimensions.single);
    } else {
      writeMarker(BjdataMarker.arrayOpen);
      for (final dimension in dimensions) {
        writeInt(dimension);
      }
      writeMarker(BjdataMarker.arrayClose);
    }
  }

  /// Serialize a payload-less schema object.
  void writeSoaFields(Map<String, BjdataSoaType> fields) {
    writeMarker(BjdataMarker.objectOpen);
    enterBlock();
    for (final field in fields.entries) {
      newLine();
      writeStringWithoutMarker(field.key);
      writeSoaType(field.value);
    }
    exitBlock();
    newLine();
    writeMarker(BjdataMarker.objectClose);
  }

  /// Serialize a single schema type specification.
  void writeSoaType(BjdataSoaType type) {
    switch (type) {
      case BjdataSoaValueType(:final marker):
        writeMarker(marker);
      case BjdataSoaBooleanType():
        writeMarker(BjdataMarker.true_);
      case BjdataSoaNullType():
        writeMarker(BjdataMarker.null_);
      case BjdataSoaFixedStringType(:final byteLength, :final huge, :final lengthMarker):
        writeMarker(huge ? BjdataMarker.huge : BjdataMarker.string);
        writeIntWithMarker(lengthMarker, byteLength);
      case BjdataSoaDictionaryType(:final values, :final huge, :final countMarker):
        writeMarker(BjdataMarker.arrayOpen);
        writeMarker(BjdataMarker.strongType);
        writeMarker(huge ? BjdataMarker.huge : BjdataMarker.string);
        writeMarker(BjdataMarker.count);
        writeIntWithMarker(countMarker, values.length);
        for (final value in values) {
          writeStringWithoutMarker(huge ? (value as BigInt).toRadixString(10) : value as String);
        }
      case BjdataSoaOffsetType(:final offsetMarker):
        writeMarker(BjdataMarker.arrayOpen);
        writeMarker(BjdataMarker.strongType);
        writeMarker(offsetMarker);
        writeMarker(BjdataMarker.arrayClose);
      case BjdataSoaObjectType(:final fields):
        writeSoaFields(fields);
      case BjdataSoaArrayType(:final elements):
        writeMarker(BjdataMarker.arrayOpen);
        for (final element in elements) {
          writeSoaType(element);
        }
        writeMarker(BjdataMarker.arrayClose);
    }
  }

  /// Serialize one field of one record into the fixed payload area.
  ///
  /// Offset-table fields write only their index here; the strings themselves are
  /// collected in [offsets] and emitted by [writeSoaOffsetTables].
  void writeSoaField(
    BjdataSoaType type,
    String name,
    String path,
    Object? value,
    Map<String, _SoaOffsetWriter> offsets,
  ) {
    switch (type) {
      case BjdataSoaNullType():
        break;
      case BjdataSoaBooleanType():
        if (value is! bool) throw _soaTypeError(name, value, 'a bool');
        writeMarker(value ? BjdataMarker.true_ : BjdataMarker.false_);
      case BjdataSoaValueType(:final marker):
        writeSoaValue(marker, name, value);
      case BjdataSoaFixedStringType(:final byteLength, :final huge):
        if (huge) {
          if (value is! BigInt) throw _soaTypeError(name, value, 'a BigInt');
          writeFixedStringContents(value.toRadixString(10), byteLength);
        } else {
          if (value is! String) throw _soaTypeError(name, value, 'a String');
          writeFixedStringContents(value, byteLength);
        }
      case BjdataSoaDictionaryType(:final values, :final huge, :final indexMarker):
        if (huge ? value is! BigInt : value is! String) {
          throw _soaTypeError(name, value, huge ? 'a BigInt' : 'a String');
        }
        final index = values.indexOf(value!);
        if (index < 0) {
          throw ArgumentError.value(value, name, 'Not present in the schema dictionary');
        }
        writeIntWithoutMarker(indexMarker, index);
      case BjdataSoaOffsetType(:final offsetMarker):
        if (value is! String) throw _soaTypeError(name, value, 'a String');
        final writer = offsets[path]!;
        writeIntWithoutMarker(offsetMarker, writer.values.length);
        writer.values.add(value);
      case BjdataSoaObjectType(:final fields):
        if (value is! Map) throw _soaTypeError(name, value, 'a Map');
        for (final field in fields.entries) {
          writeSoaField(
            field.value,
            field.key,
            '$path.${field.key}',
            _soaRecordValue(value.cast<String, Object?>(), field.key),
            offsets,
          );
        }
      case BjdataSoaArrayType(:final elements):
        if (value is! List) throw _soaTypeError(name, value, 'a List');
        if (value.length != elements.length) {
          throw ArgumentError.value(value, name, 'Expected ${elements.length} elements, got ${value.length}');
        }
        for (var i = 0; i < elements.length; i++) {
          writeSoaField(elements[i], '$name[$i]', '$path[$i]', value[i], offsets);
        }
    }
  }

  /// Serialize a fixed-length payload value of type [marker].
  void writeSoaValue(BjdataMarker marker, String name, Object? value) {
    switch (marker) {
      case BjdataMarker.char:
        if (value is! String || value.length != 1) throw _soaTypeError(name, value, 'a single-character String');
        final code = value.codeUnitAt(0);
        if (code > 127) throw ArgumentError.value(value, name, 'char values must be ASCII (0-127)');
        writeIntWithoutMarker(BjdataMarker.uint8, code);
      case BjdataMarker.byte:
        if (value is! int) throw _soaTypeError(name, value, 'an int');
        writeIntWithoutMarker(BjdataMarker.uint8, value);
      case BjdataMarker.float16 || BjdataMarker.float32 || BjdataMarker.float64:
        if (value is! num) throw _soaTypeError(name, value, 'a num');
        writeFloatWithoutMarker(marker, value.toDouble());
      default:
        if (value is! int) throw _soaTypeError(name, value, 'an int');
        writeIntWithoutMarker(marker, value);
    }
  }

  static ArgumentError _soaTypeError(String name, Object? value, String expected) =>
      ArgumentError.value(value, name, 'Expected $expected for this SoA field');

  /// Serialize a string padded to exactly [byteLength] UTF-8 bytes.
  void writeFixedStringContents(String string, int byteLength) {
    final length = utf8.encode(string).length;
    if (length > byteLength) {
      throw ArgumentError.value(string, 'value', 'Does not fit in $byteLength bytes');
    }
    writeStringContents(string);
    writePadding(byteLength - length);
  }

  /// Serialize the offset table and string buffer of every offset-table field.
  void writeSoaOffsetTables(Map<String, _SoaOffsetWriter> offsets) {
    for (final writer in offsets.values) {
      final marker = writer.type.offsetMarker;
      newLine();
      var offset = 0;
      writeIntWithoutMarker(marker, offset);
      for (final value in writer.values) {
        offset += utf8.encode(value).length;
        writeIntWithoutMarker(marker, offset);
      }
      newLine();
      for (final value in writer.values) {
        writeStringContents(value);
      }
    }
  }
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

  BjdataBufferWriter(
    dynamic Function(dynamic o)? toEncodable,
    this.bufferSize,
    this.addChunk, {
    BjdataConfig config = const BjdataConfig(),
  })  : buffer = Uint8List(bufferSize),
        super(toEncodable, config);

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
    void Function(Uint8List chunk) addChunk, {
    BjdataConfig config = const BjdataConfig(),
  }) {
    final encoder = BjdataBufferWriter(toEncodable, bufferSize, addChunk, config: config);
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
  // ignore: unnecessary_cast (https://github.com/dart-lang/sdk/issues/52801)
  void writeStringContents(String string) => writeBytes(utf8.encode(string) as Uint8List);

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
  void writeFloatWithoutMarker(BjdataMarker marker, double number) {
    writeBytes(switch (marker) {
      BjdataMarker.float16 => (ByteData(2)..setUint16(0, float16Bits(number), Endian.little)).buffer.asUint8List(),
      BjdataMarker.float32 => (ByteData(4)..setFloat32(0, number, Endian.little)).buffer.asUint8List(),
      BjdataMarker.float64 => (ByteData(8)..setFloat64(0, number, Endian.little)).buffer.asUint8List(),
      _ => throw ArgumentError.value(marker, 'marker', 'Not a valid float marker'),
    });
  }

  @override
  void writePadding(int count) {
    if (count > 0) writeBytes(Uint8List(count));
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
    this._indent, {
    BjdataConfig config = const BjdataConfig(),
  }) : super(toEncodable, config);

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
    String? indent, {
    BjdataConfig config = const BjdataConfig(),
  }) {
    var output = StringBuffer();
    printOn(object, output, toEncodable, indent, config: config);
    return output.toString();
  }

  /// Convert object to a string, and write the result to the [output] sink.
  ///
  /// The result is written piecemally to the sink.
  static void printOn(
    Object? object,
    StringSink output,
    dynamic Function(dynamic o)? toEncodable,
    String? indent, {
    BjdataConfig config = const BjdataConfig(),
  }) {
    BjdataBlockNotationStringifier(output, toEncodable, indent, config: config).write(object);
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
  void writeFloatWithoutMarker(BjdataMarker marker, double number) => writeBlock(number.toString());

  @override
  void writePadding(int count) {
    for (var i = 0; i < count; i++) {
      writeBlock('0');
    }
  }

  @override
  void enterBlock() => _indentLevel++;

  @override
  void exitBlock() => _indentLevel--;

  @override
  void newLine() {
    writeNewLine();
    writeIndentation(_indentLevel);
  }

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

/// Collects the strings of one offset-table backed SoA field while the fixed
/// payload is being written.
class _SoaOffsetWriter {
  _SoaOffsetWriter(this.type);

  final BjdataSoaOffsetType type;
  final List<String> values = [];
}

/// The IEEE 754 half-precision bit pattern of [value], rounded to nearest even.
int float16Bits(double value) {
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
