import 'dart:convert';
import 'dart:typed_data';

import '../marker.dart';
import '../soa.dart';

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
    if (_offset + length > _bytes.lengthInBytes) {
      throw FormatException("Unexpected end of input", _bytes, _bytes.lengthInBytes);
    }
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

  /// The `E` marker of the draft 4 extension type, which is not supported.
  ///
  /// TODO: Extension types have no one-to-one JSON representation, so they are
  /// rejected rather than guessed at. See
  /// https://github.com/NeuroJSON/bjdata/issues/33.
  static const int _extensionMarkerValue = 0x45;

  BjdataMarker _peekMarker() {
    final v = _peek();
    final marker = BjdataMarker.fromValueOrNull(v);
    if (marker == null) {
      throw FormatException(
        v == _extensionMarkerValue
            ? "BJData extension types ('E') are not supported"
            : 'Invalid BJData marker: 0x${v.toRadixString(16).padLeft(2, '0')}',
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

  int _readIntForMarker(BjdataMarker marker, String what, int offsetBefore) => switch (marker) {
        BjdataMarker.uint8 => _readUint8(),
        BjdataMarker.int8 => _readInt8(),
        BjdataMarker.uint16 => _readUint16(),
        BjdataMarker.int16 => _readInt16(),
        BjdataMarker.uint32 => _readUint32(),
        BjdataMarker.int32 => _readInt32(),
        BjdataMarker.uint64 => _readUint64(),
        BjdataMarker.int64 => _readInt64(),
        _ => throw FormatException('Unexpected non-$what type marker: $marker', _bytes, offsetBefore),
      };

  int _readLength() {
    final offsetBefore = _offset;
    final length = _readIntForMarker(_readMarker(), 'length', offsetBefore);
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

  /// The element count of a container, and the dimensions it was given as.
  ///
  /// A count is either a single integer, a dimension array (`#[Nx Ny ...]`) for
  /// an N-dimensional array serialized in row-major order, or a dimension array
  /// wrapped in a single element array (`#[[Nx Ny ...]]`) for one serialized in
  /// column-major order, as MATLAB and FORTRAN write it.
  ({int count, List<int>? dimensions, bool columnMajor}) _readCount() {
    final offsetBefore = _offset;
    if (!_peekMarkerConsumeIf(BjdataMarker.arrayOpen)) {
      return (count: _readLength(), dimensions: null, columnMajor: false);
    }

    // A second '[' wraps the dimension array, which marks column-major order.
    final columnMajor = _peekMarker() == BjdataMarker.arrayOpen;
    if (columnMajor) _offset++;

    final dimensions = _readDimensions(offsetBefore);

    if (columnMajor && !_peekMarkerConsumeIf(BjdataMarker.arrayClose)) {
      throw FormatException('Expected end of the wrapped dimension array', _bytes, _offset);
    }
    return (
      count: dimensions.fold(1, (a, b) => a * b),
      dimensions: dimensions,
      columnMajor: columnMajor,
    );
  }

  /// Reads a dimension array, with its leading `[` already consumed.
  List<int> _readDimensions(int offsetBefore) {
    BjdataMarker? strongType;
    int? count;

    if (_peekMarkerConsumeIf(BjdataMarker.strongType)) {
      strongType = _readMarker();
      if (!strongType.isIntegerType) {
        throw FormatException('Dimensions must be of an integer type: $strongType', _bytes, _offset - 1);
      }
      if (!_peekMarkerConsumeIf(BjdataMarker.count)) {
        throw FormatException('Expected count marker to follow strong type', _bytes, _offset);
      }
      count = _readLength();
    } else if (_peekMarkerConsumeIf(BjdataMarker.count)) {
      count = _readLength();
    }

    final dimensions = <int>[];
    for (var i = 0; count != null ? i < count : true; i++) {
      if (count == null && _peekMarkerConsumeIf(BjdataMarker.arrayClose)) break;
      final before = _offset;
      final dimension = _readIntForMarker(strongType ?? _readMarker(), 'dimension', before);
      if (dimension < 0) throw FormatException('Negative dimension: $dimension', _bytes, before);
      dimensions.add(dimension);
    }
    if (dimensions.isEmpty) throw FormatException('Empty dimension array', _bytes, offsetBefore);
    return dimensions;
  }

  /// The header of a container: the type of its elements, and how many there are.
  ///
  /// A `$` introduces either a strong type, shared by every element, or, when a
  /// `{` follows it, the field definitions of a Structure-of-Arrays container.
  /// Either way a count must follow. An untyped container may still be counted,
  /// and an untyped, uncounted one is terminated by its closing marker instead,
  /// for which every field here is null.
  ({BjdataMarker? strongType, BjdataSoaSchema? soaSchema, int? count, List<int>? dimensions, bool columnMajor})
      _readStrongTypeAndCount() {
    if (!_peekMarkerConsumeIf(BjdataMarker.strongType)) {
      if (!_peekMarkerConsumeIf(BjdataMarker.count)) {
        return (strongType: null, soaSchema: null, count: null, dimensions: null, columnMajor: false);
      }

      // Read count
      final (:count, :dimensions, :columnMajor) = _readCount();
      return (strongType: null, soaSchema: null, count: count, dimensions: dimensions, columnMajor: columnMajor);
    }

    // A '{' in place of a type marker introduces an SoA schema
    final soaSchema = _peekMarkerConsumeIf(BjdataMarker.objectOpen) ? BjdataSoaSchema(_readSoaFields()) : null;

    // Read strong type
    BjdataMarker? strongType;
    if (soaSchema == null) {
      strongType = _readMarker();
      if (!strongType.isValidStrongType) {
        throw FormatException('Invalid strong type: $strongType', _bytes, _offset - 1);
      }
    }

    // Must be followed by count
    final countMarker = _readUint8();
    if (countMarker != BjdataMarker.count.value) {
      throw FormatException(
        'Expected count marker to follow ${soaSchema != null ? 'SoA schema' : 'strong type'}: '
        'got 0x${countMarker.toRadixString(16).padLeft(2, '0')} / ${BjdataMarker.fromValueOrNull(countMarker)}',
        _bytes,
        _offset - 1,
      );
    }

    // Read count
    final offsetBefore = _offset;
    final (:count, :dimensions, :columnMajor) = _readCount();

    // An SoA container shares the dimension handling of an N-dimensional array,
    // except that the wrapped form is refused: it states its ordering with its
    // container marker, so a wrapper would be a second, conflicting answer.
    if (soaSchema != null && columnMajor) {
      throw FormatException(
        'An SoA container states its ordering with its container marker, '
        'not with a wrapped dimension array',
        _bytes,
        offsetBefore,
      );
    }

    return (
      strongType: strongType,
      soaSchema: soaSchema,
      count: count,
      dimensions: dimensions,
      columnMajor: columnMajor,
    );
  }

  Object _readArray() {
    final offsetBefore = _offset - 1;
    final (:strongType, :soaSchema, :count, :dimensions, :columnMajor) = _readStrongTypeAndCount();

    if (soaSchema != null) {
      return _readSoa(soaSchema, dimensions ?? [count!], columnMajor: false);
    }

    if (strongType != null && strongType.isValidStrongType && strongType != BjdataMarker.char) {
      final flat = switch (strongType) {
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
      if (dimensions == null) return flat;
      return _reshape(columnMajor ? _toRowMajor(flat, dimensions) : flat, dimensions, 0);
    }

    final list = <Object?>[];
    for (var i = 0; count != null ? i < count : true; i++) {
      while (strongType == null && _peekMarkerConsumeIf(BjdataMarker.noop)) {}
      if (count == null && _peekMarkerConsumeIf(BjdataMarker.arrayClose)) break;
      final value = _readValueForMarker(strongType ?? _readMarker());
      list.add(_reviver == null ? value : _reviver!(i, value));
    }
    if (dimensions == null) return list;
    return _reshape(columnMajor ? _toRowMajor(list, dimensions) : list, dimensions, 0);
  }

  /// Nests [flat] according to [dimensions], one list per axis.
  ///
  /// Slices are views onto [flat] wherever it is a typed list, so an
  /// N-dimensional array still holds a single contiguous buffer once decoded.
  Object _reshape(Object flat, List<int> dimensions, int axis) {
    if (axis == dimensions.length - 1) return flat;

    var stride = 1;
    for (var i = axis + 1; i < dimensions.length; i++) {
      stride *= dimensions[i];
    }
    return [
      for (var i = 0; i < dimensions[axis]; i++)
        _reshape(_slice(flat, i * stride, (i + 1) * stride), dimensions, axis + 1),
    ];
  }

  /// A view of [list] from [start] to [end], keeping its type.
  Object _slice(Object list, int start, int end) => switch (list) {
        ByteData l => ByteData.sublistView(l, start, end),
        Uint8List l => Uint8List.sublistView(l, start, end),
        Int8List l => Int8List.sublistView(l, start, end),
        Uint16List l => Uint16List.sublistView(l, start, end),
        Int16List l => Int16List.sublistView(l, start, end),
        Uint32List l => Uint32List.sublistView(l, start, end),
        Int32List l => Int32List.sublistView(l, start, end),
        Float32List l => Float32List.sublistView(l, start, end),
        Float64List l => Float64List.sublistView(l, start, end),
        // Not reachable on the web, where 64 bit lists decode as List<int>.
        Uint64List l => Uint64List.sublistView(l, start, end),
        Int64List l => Int64List.sublistView(l, start, end),
        List l => l.sublist(start, end),
        _ => throw FormatException('Cannot reshape ${list.runtimeType}', _bytes, _offset),
      };

  /// Reorders column-major [flat] into row-major order.
  ///
  /// The elements are permuted rather than reinterpreted, so the result reads
  /// the same way a row-major array of the same shape would.
  Object _toRowMajor(Object flat, List<int> dimensions) {
    final rank = dimensions.length;
    if (rank < 2) return flat;

    // In column-major order the first axis varies fastest.
    final strides = List<int>.filled(rank, 1);
    for (var axis = 1; axis < rank; axis++) {
      strides[axis] = strides[axis - 1] * dimensions[axis - 1];
    }

    final total = dimensions.fold(1, (a, b) => a * b);
    final source = List<int>.filled(total, 0);
    final indices = List<int>.filled(rank, 0);
    for (var i = 0; i < total; i++) {
      var offset = 0;
      for (var axis = 0; axis < rank; axis++) {
        offset += indices[axis] * strides[axis];
      }
      source[i] = offset;
      // Step through the output in row-major order, last axis fastest.
      for (var axis = rank - 1; axis >= 0; axis--) {
        if (++indices[axis] < dimensions[axis]) break;
        indices[axis] = 0;
      }
    }

    if (flat is List) return [for (final index in source) flat[index]];

    // Permute whole elements, whatever their width, and reinterpret the result
    // as the same kind of list.
    final data = flat as TypedData;
    final size = data.elementSizeInBytes;
    final bytes = Uint8List.sublistView(data);
    final reordered = Uint8List(bytes.length);
    for (var i = 0; i < total; i++) {
      reordered.setRange(i * size, (i + 1) * size, bytes, source[i] * size);
    }
    return _sameTypeAs(data, reordered);
  }

  /// Reinterprets [bytes] as the same kind of list as [like].
  Object _sameTypeAs(TypedData like, Uint8List bytes) => switch (like) {
        ByteData() => ByteData.sublistView(bytes),
        Uint8List() => bytes,
        Int8List() => Int8List.sublistView(bytes),
        Uint16List() => Uint16List.sublistView(bytes),
        Int16List() => Int16List.sublistView(bytes),
        Uint32List() => Uint32List.sublistView(bytes),
        Int32List() => Int32List.sublistView(bytes),
        Float32List() => Float32List.sublistView(bytes),
        Float64List() => Float64List.sublistView(bytes),
        Uint64List() => Uint64List.sublistView(bytes),
        Int64List() => Int64List.sublistView(bytes),
        _ => throw FormatException('Cannot reorder ${like.runtimeType}', _bytes, _offset),
      };

  Map<String, Object?>? _readMap() {
    final offsetBefore = _offset;
    final (:strongType, :soaSchema, :count, :dimensions, columnMajor: _) = _readStrongTypeAndCount();

    if (soaSchema != null) {
      return _readSoa(soaSchema, dimensions ?? [count!], columnMajor: true) as Map<String, Object?>;
    }

    if (dimensions != null) {
      throw FormatException('An object cannot be counted by a dimension array', _bytes, offsetBefore);
    }

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

  Object? _revive(Object? key, Object? value) => _reviver == null ? value : _reviver!(key, value);

  // --- Structure-of-Arrays (draft 4) ---

  /// Reads the payload of an SoA container, whose [schema] and [dimensions] have
  /// already been read from its header.
  ///
  /// [columnMajor] selects between the `{$` (columnar) and `[$` (interleaved)
  /// layouts, which share the same schema and count header.
  ///
  /// A row-major container decodes to a [List] of record [Map]s and a
  /// column-major one to a [Map] of column [List]s. N-dimensional containers are
  /// nested according to their dimensions, so a `4x3` grid of records decodes to
  /// a list of four lists of three records.
  Object _readSoa(BjdataSoaSchema schema, List<int> dimensions, {required bool columnMajor}) {
    final count = dimensions.fold(1, (a, b) => a * b);

    final offsetFields = {
      for (final field in schema.offsetFields.entries) field.key: _SoaOffsetField(field.value),
    };

    if (columnMajor) {
      final columns = {
        for (final name in schema.fields.keys) name: List<Object?>.filled(count, null, growable: false),
      };
      for (final field in schema.fields.entries) {
        final column = columns[field.key]!;
        for (var record = 0; record < count; record++) {
          _readSoaField(field.value, field.key, field.key, offsetFields, (v) => column[record] = v);
        }
      }
      _readSoaOffsetTables(offsetFields, count);
      return {
        for (final column in columns.entries) column.key: reshapeBjdataSoa(column.value, dimensions),
      };
    }

    final records = List.generate(count, (_) => <String, Object?>{}, growable: false);
    for (final record in records) {
      for (final field in schema.fields.entries) {
        _readSoaField(field.value, field.key, field.key, offsetFields, (v) => record[field.key] = v);
      }
    }
    _readSoaOffsetTables(offsetFields, count);
    return reshapeBjdataSoa(records, dimensions);
  }

  /// Reads the field definitions of a schema, with the leading `{` already consumed.
  Map<String, BjdataSoaType> _readSoaFields() {
    final fields = <String, BjdataSoaType>{};
    while (!_peekMarkerConsumeIf(BjdataMarker.objectClose)) {
      final offsetBefore = _offset;
      final name = _readString();
      if (fields.containsKey(name)) {
        throw FormatException("Duplicate SoA schema field '$name'", _bytes, offsetBefore);
      }
      fields[name] = _readSoaType();
    }
    if (fields.isEmpty) throw FormatException('Empty SoA schema', _bytes, _offset - 1);
    return fields;
  }

  /// Reads a single schema type specification.
  BjdataSoaType _readSoaType() {
    final offsetBefore = _offset;
    final marker = _readMarker();
    switch (marker) {
      case BjdataMarker.true_:
        return const BjdataSoaBooleanType();
      case BjdataMarker.null_:
        return const BjdataSoaNullType();
      case BjdataMarker.string:
      case BjdataMarker.huge:
        final lengthMarker = _peekMarker();
        return BjdataSoaFixedStringType(
          _readLength(),
          huge: marker == BjdataMarker.huge,
          lengthMarker: lengthMarker,
        );
      case BjdataMarker.objectOpen:
        return BjdataSoaObjectType(_readSoaFields());
      case BjdataMarker.arrayOpen:
        return _readSoaArrayType();
      default:
        if (marker.isValidStrongType) return BjdataSoaValueType(marker);
        throw FormatException('Invalid SoA schema type marker: $marker', _bytes, offsetBefore);
    }
  }

  /// Reads an `[`-prefixed schema type: a dictionary, an offset table or a fixed array.
  BjdataSoaType _readSoaArrayType() {
    if (_peekMarkerConsumeIf(BjdataMarker.strongType)) {
      final offsetBefore = _offset;
      final type = _readMarker();

      if (_peekMarkerConsumeIf(BjdataMarker.arrayClose)) {
        if (!type.isIntegerType) {
          throw FormatException('SoA offset table type must be an integer type', _bytes, offsetBefore);
        }
        return BjdataSoaOffsetType(type);
      }

      if (_peekMarkerConsumeIf(BjdataMarker.count)) {
        final huge = type == BjdataMarker.huge;
        if (type != BjdataMarker.string && !huge) {
          throw FormatException('SoA dictionary type must be S or H', _bytes, offsetBefore);
        }
        final countMarker = _peekMarker();
        final count = _readLength();
        if (count == 0) throw FormatException('Empty SoA dictionary', _bytes, offsetBefore);
        return BjdataSoaDictionaryType(
          [for (var i = 0; i < count; i++) huge ? BigInt.parse(_readString()) : _readString()],
          huge: huge,
          countMarker: countMarker,
        );
      }

      throw FormatException("Expected ']' or '#' after SoA schema type marker", _bytes, _offset);
    }

    final elements = <BjdataSoaType>[];
    while (!_peekMarkerConsumeIf(BjdataMarker.arrayClose)) {
      elements.add(_readSoaType());
    }
    if (elements.isEmpty) throw FormatException('Empty SoA fixed array', _bytes, _offset - 1);
    return BjdataSoaArrayType(elements);
  }

  /// Reads one field of one record from the fixed payload area.
  ///
  /// Offset-table fields cannot be resolved until the tables that follow the
  /// payload have been read, so they register their index and a callback with
  /// the matching [_SoaOffsetField] instead of assigning a value.
  void _readSoaField(
    BjdataSoaType type,
    String name,
    String path,
    Map<String, _SoaOffsetField> offsetFields,
    void Function(Object?) assign,
  ) {
    switch (type) {
      case BjdataSoaNullType():
        assign(_revive(name, null));
      case BjdataSoaBooleanType():
        final offsetBefore = _offset;
        assign(_revive(
            name,
            switch (_bytes.getUint8(_offsetIncrement(1))) {
              BjdataReader._trueByte => true,
              BjdataReader._falseByte => false,
              final b => throw FormatException(
                  'Invalid SoA boolean byte: 0x${b.toRadixString(16).padLeft(2, '0')}',
                  _bytes,
                  offsetBefore,
                ),
            }));
      case BjdataSoaValueType(:final marker):
        assign(_revive(name, _readValueForMarker(marker)));
      case BjdataSoaFixedStringType(:final byteLength, :final huge):
        final value = _readSoaFixedString(byteLength);
        assign(_revive(name, huge ? BigInt.parse(value) : value));
      case BjdataSoaDictionaryType(:final values, :final indexMarker):
        final offsetBefore = _offset;
        final index = _readIntForMarker(indexMarker, 'index', offsetBefore);
        if (index < 0 || index >= values.length) {
          throw FormatException('SoA dictionary index out of range: $index', _bytes, offsetBefore);
        }
        assign(_revive(name, values[index]));
      case BjdataSoaOffsetType(:final offsetMarker):
        final offsetBefore = _offset;
        // Claim the slot now so that the field keeps its schema position; the
        // value itself only becomes known once the offset tables are read.
        assign(null);
        offsetFields[path]!
          ..indices.add(_readIntForMarker(offsetMarker, 'offset', offsetBefore))
          ..assigns.add((value) => assign(_revive(name, value)));
      case BjdataSoaObjectType(:final fields):
        final map = <String, Object?>{};
        assign(map);
        for (final field in fields.entries) {
          _readSoaField(field.value, field.key, '$path.${field.key}', offsetFields, (v) => map[field.key] = v);
        }
      case BjdataSoaArrayType(:final elements):
        final list = List<Object?>.filled(elements.length, null, growable: false);
        assign(list);
        for (var i = 0; i < elements.length; i++) {
          _readSoaField(elements[i], '$name[$i]', '$path[$i]', offsetFields, (v) => list[i] = v);
        }
    }
  }

  static const int _trueByte = 0x54;
  static const int _falseByte = 0x46;

  /// Reads a fixed-length string field, stripping the null padding.
  String _readSoaFixedString(int byteLength) {
    final bytes = _readUint8ListView(byteLength);
    var end = bytes.length;
    while (end > 0 && bytes[end - 1] == 0) {
      end--;
    }
    return utf8.decode(Uint8List.sublistView(bytes, 0, end));
  }

  /// Reads the offset table and string buffer appended after the payload for
  /// each offset-table field, and resolves the values they stand in for.
  void _readSoaOffsetTables(Map<String, _SoaOffsetField> offsetFields, int count) {
    for (final field in offsetFields.values) {
      final marker = field.type.offsetMarker;
      final table = <int>[];
      for (var i = 0; i <= count; i++) {
        final offsetBefore = _offset;
        final offset = _readIntForMarker(marker, 'offset', offsetBefore);
        if (offset < 0) throw FormatException('Negative SoA offset: $offset', _bytes, offsetBefore);
        table.add(offset);
      }

      final bufferOffset = _offset;
      final buffer = _readUint8ListView(table.last);
      for (var i = 0; i < field.indices.length; i++) {
        final index = field.indices[i];
        if (index < 0 || index + 1 >= table.length) {
          throw FormatException('SoA offset index out of range: $index', _bytes, bufferOffset);
        }
        final start = table[index];
        final end = table[index + 1];
        if (start > end || end > buffer.length) {
          throw FormatException('Invalid SoA offset range: $start..$end', _bytes, bufferOffset);
        }
        field.assigns[i](utf8.decode(Uint8List.sublistView(buffer, start, end)));
      }
    }
  }
}

/// Collects the payload indices and pending assignments of one offset-table
/// backed SoA field while the fixed payload is being read.
class _SoaOffsetField {
  _SoaOffsetField(this.type);

  final BjdataSoaOffsetType type;
  final List<int> indices = [];
  final List<void Function(String)> assigns = [];
}
