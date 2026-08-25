import 'dart:convert';
import 'dart:typed_data';

import 'marker.dart';

/// How a list that is a uniform table of records is written.
///
/// Detection is the same in every case: a list of two or more records sharing
/// the same field names and per-field types, or rectangular nested lists of
/// them. Only the layout of the payload differs.
enum BjdataSoaLayout {
  /// Never write Structure-of-Arrays containers.
  ///
  /// Tables are written as plain arrays of objects, which is what a decoder that
  /// only understands BJData draft 3 expects.
  off,

  /// Row-major (`[$`): whole records are stored contiguously.
  ///
  /// Decodes back to a [List] of record [Map]s, matching what was encoded.
  rowMajor,

  /// Column-major (`{$`): all values of a field are stored contiguously.
  ///
  /// Holds the same schema and exactly as many payload bytes as [rowMajor], so
  /// the choice is about access rather than size: a column is a single
  /// contiguous run, which suits a reader that walks fields rather than records.
  ///
  /// A column-major container is an object of named arrays, so it decodes to a
  /// [Map] of column [List]s rather than to the list of records that produced
  /// it.
  columnMajor,
}

/// A field type within a [BjdataSoaSchema].
///
/// Every schema field declares a fixed number of payload bytes per record, so
/// that an SoA payload can be traversed without inspecting its contents.
sealed class BjdataSoaType {
  const BjdataSoaType();

  /// The number of payload bytes each record contributes for this field.
  int get payloadByteLength;
}

/// A fixed-length numeric, [BjdataMarker.char] or [BjdataMarker.byte] field.
///
/// The [marker] must be one of `U i u I l m L M h d D C B`.
final class BjdataSoaValueType extends BjdataSoaType {
  /// The type marker of the field.
  final BjdataMarker marker;

  BjdataSoaValueType(this.marker) {
    if (!marker.isValidStrongType) {
      throw ArgumentError.value(marker, 'marker', 'Not a valid SoA value type');
    }
  }

  @override
  int get payloadByteLength => marker.fixedByteLength!;

  @override
  bool operator ==(Object other) => other is BjdataSoaValueType && other.marker == marker;

  @override
  int get hashCode => Object.hash(BjdataSoaValueType, marker);

  @override
  String toString() => 'BjdataSoaValueType(${marker.ascii})';
}

/// A boolean field, declared with `T` and stored as a single `T`/`F` byte.
final class BjdataSoaBooleanType extends BjdataSoaType {
  const BjdataSoaBooleanType();

  @override
  int get payloadByteLength => 1;

  @override
  bool operator ==(Object other) => other is BjdataSoaBooleanType;

  @override
  int get hashCode => Object.hash(BjdataSoaBooleanType, null);

  @override
  String toString() => 'BjdataSoaBooleanType()';
}

/// A null/placeholder field, declared with `Z` and occupying no payload bytes.
final class BjdataSoaNullType extends BjdataSoaType {
  const BjdataSoaNullType();

  @override
  int get payloadByteLength => 0;

  @override
  bool operator ==(Object other) => other is BjdataSoaNullType;

  @override
  int get hashCode => Object.hash(BjdataSoaNullType, null);

  @override
  String toString() => 'BjdataSoaNullType()';
}

/// A fixed-length string (`S`) or high-precision number (`H`) field.
///
/// Each record contributes exactly [byteLength] bytes with no length prefix.
/// Values shorter than [byteLength] are right-padded with null bytes, which are
/// stripped again when decoding.
///
/// Never chosen by [BjdataSoaSchema.tryInfer], because that padding is lossy for
/// values that themselves end in null bytes.
final class BjdataSoaFixedStringType extends BjdataSoaType {
  /// The number of payload bytes reserved for the value.
  final int byteLength;

  /// Whether the field holds a high-precision number (`H`) rather than a string (`S`).
  ///
  /// High-precision fields decode to [BigInt].
  final bool huge;

  /// The integer marker used to encode [byteLength] in the schema.
  ///
  /// If null, the smallest marker that fits is used.
  final BjdataMarker? lengthMarker;

  BjdataSoaFixedStringType(this.byteLength, {this.huge = false, this.lengthMarker}) {
    if (byteLength < 0) {
      throw ArgumentError.value(byteLength, 'byteLength', 'Must be non-negative');
    }
    if (lengthMarker != null && !lengthMarker!.isIntegerType) {
      throw ArgumentError.value(lengthMarker, 'lengthMarker', 'Not an integer marker');
    }
  }

  @override
  int get payloadByteLength => byteLength;

  @override
  bool operator ==(Object other) =>
      other is BjdataSoaFixedStringType && other.byteLength == byteLength && other.huge == huge;

  @override
  int get hashCode => Object.hash(BjdataSoaFixedStringType, byteLength, huge);

  @override
  String toString() => 'BjdataSoaFixedStringType($byteLength, huge: $huge)';
}

/// A dictionary-backed string (`[$S#n...`) or high-precision (`[$H#n...`) field.
///
/// The schema embeds the full set of possible [values]; each record stores only
/// an unsigned index into that dictionary. This is the most compact encoding for
/// low-cardinality categorical data.
final class BjdataSoaDictionaryType extends BjdataSoaType {
  /// The dictionary entries, indexed by their position.
  ///
  /// [String] entries when [huge] is false, [BigInt] entries when it is true.
  final List<Object> values;

  /// Whether the entries are high-precision numbers (`H`) rather than strings (`S`).
  final bool huge;

  /// The integer marker used to encode the dictionary count in the schema.
  ///
  /// If null, the smallest marker that fits is used.
  final BjdataMarker? countMarker;

  BjdataSoaDictionaryType(this.values, {this.huge = false, this.countMarker}) {
    if (values.isEmpty) {
      throw ArgumentError.value(values, 'values', 'Dictionary must not be empty');
    }
    if (countMarker != null && !countMarker!.isIntegerType) {
      throw ArgumentError.value(countMarker, 'countMarker', 'Not an integer marker');
    }
  }

  /// The unsigned integer marker used to store indices in the payload.
  ///
  /// Determined by the dictionary size, per the BJData specification.
  BjdataMarker get indexMarker => switch (values.length) {
        <= 255 => BjdataMarker.uint8,
        <= 65535 => BjdataMarker.uint16,
        <= 4294967295 => BjdataMarker.uint32,
        _ => BjdataMarker.uint64,
      };

  @override
  int get payloadByteLength => indexMarker.fixedByteLength!;

  @override
  bool operator ==(Object other) =>
      other is BjdataSoaDictionaryType &&
      other.huge == huge &&
      other.values.length == values.length &&
      Iterable.generate(values.length).every((i) => other.values[i] == values[i]);

  @override
  int get hashCode => Object.hash(BjdataSoaDictionaryType, huge, Object.hashAll(values));

  @override
  String toString() => 'BjdataSoaDictionaryType($values, huge: $huge)';
}

/// An offset-table backed variable-length string field (`[$<int-type>]`).
///
/// Each record stores an index of type [offsetMarker] in the fixed payload area.
/// After the payload, an offset table of `count + 1` entries and a concatenated
/// string buffer are appended, one pair per offset field in schema order.
///
/// The BJData specification encodes offset-based high-precision numbers
/// identically to offset-based strings, so decoding always yields [String]
/// values.
final class BjdataSoaOffsetType extends BjdataSoaType {
  /// The integer marker used for the payload index and the offset table entries.
  final BjdataMarker offsetMarker;

  BjdataSoaOffsetType(this.offsetMarker) {
    if (!offsetMarker.isIntegerType) {
      throw ArgumentError.value(offsetMarker, 'offsetMarker', 'Not an integer marker');
    }
  }

  @override
  int get payloadByteLength => offsetMarker.fixedByteLength!;

  @override
  bool operator ==(Object other) => other is BjdataSoaOffsetType && other.offsetMarker == offsetMarker;

  @override
  int get hashCode => Object.hash(BjdataSoaOffsetType, offsetMarker);

  @override
  String toString() => 'BjdataSoaOffsetType(${offsetMarker.ascii})';
}

/// A nested object field (`{...}`), decoded as a [Map].
final class BjdataSoaObjectType extends BjdataSoaType {
  /// The nested fields, in payload order.
  final Map<String, BjdataSoaType> fields;

  BjdataSoaObjectType(this.fields) {
    if (fields.isEmpty) {
      throw ArgumentError.value(fields, 'fields', 'Nested object must not be empty');
    }
  }

  @override
  int get payloadByteLength => fields.values.fold(0, (sum, f) => sum + f.payloadByteLength);

  @override
  bool operator ==(Object other) =>
      other is BjdataSoaObjectType &&
      other.fields.length == fields.length &&
      fields.entries.every((e) => other.fields[e.key] == e.value);

  @override
  int get hashCode => Object.hash(BjdataSoaObjectType, Object.hashAll(fields.keys), Object.hashAll(fields.values));

  @override
  String toString() => 'BjdataSoaObjectType($fields)';
}

/// A fixed-length array field (`[...]`), decoded as a [List].
///
/// The schema lists one type marker per element, so `[D D D]` declares an array
/// of three float64 values.
final class BjdataSoaArrayType extends BjdataSoaType {
  /// The element types, in payload order.
  final List<BjdataSoaType> elements;

  BjdataSoaArrayType(this.elements) {
    if (elements.isEmpty) {
      throw ArgumentError.value(elements, 'elements', 'Fixed array must not be empty');
    }
  }

  @override
  int get payloadByteLength => elements.fold(0, (sum, e) => sum + e.payloadByteLength);

  @override
  bool operator ==(Object other) =>
      other is BjdataSoaArrayType &&
      other.elements.length == elements.length &&
      Iterable.generate(elements.length).every((i) => other.elements[i] == elements[i]);

  @override
  int get hashCode => Object.hash(BjdataSoaArrayType, Object.hashAll(elements));

  @override
  String toString() => 'BjdataSoaArrayType($elements)';
}

/// The payload-less object that describes the record structure of a
/// Structure-of-Arrays container.
final class BjdataSoaSchema {
  /// The fields of the schema, in payload order.
  final Map<String, BjdataSoaType> fields;

  const BjdataSoaSchema(this.fields);

  /// The number of fixed payload bytes contributed by a single record.
  ///
  /// Does not include the offset tables and string buffers appended after the
  /// payload for [BjdataSoaOffsetType] fields.
  int get recordByteLength => fields.values.fold(0, (sum, f) => sum + f.payloadByteLength);

  /// The [BjdataSoaOffsetType] fields of this schema, in payload order.
  ///
  /// Keys are payload paths: `field`, `field.nested` for a field of a nested
  /// object, and `field[0]` for an element of a fixed array. Each entry owns one
  /// offset table and string buffer, appended after the payload in this order.
  Map<String, BjdataSoaOffsetType> get offsetFields {
    final result = <String, BjdataSoaOffsetType>{};
    late final void Function(Map<String, BjdataSoaType>, String) visitFields;

    void visitType(BjdataSoaType type, String path) {
      switch (type) {
        case BjdataSoaOffsetType():
          result[path] = type;
        case BjdataSoaObjectType(:final fields):
          visitFields(fields, path);
        case BjdataSoaArrayType(:final elements):
          for (var i = 0; i < elements.length; i++) {
            visitType(elements[i], '$path[$i]');
          }
        default:
          break;
      }
    }

    visitFields = (fields, prefix) {
      for (final field in fields.entries) {
        visitType(field.value, prefix.isEmpty ? field.key : '$prefix.${field.key}');
      }
    };

    visitFields(fields, '');
    return result;
  }

  /// Derives a schema from [records], or returns null if they cannot be stored
  /// as a Structure-of-Arrays without changing any value.
  ///
  /// A field is only given a type when every record agrees on it:
  ///
  /// - all-null fields become [BjdataSoaNullType]
  /// - `bool` fields become [BjdataSoaBooleanType]
  /// - `int` fields use the smallest integer marker covering their range,
  ///   favouring unsigned types
  /// - `double` fields become `float64`
  /// - `String` fields become a [BjdataSoaDictionaryType] when at most half the
  ///   values are distinct, and a [BjdataSoaOffsetType] otherwise
  /// - `BigInt` fields become a high-precision [BjdataSoaDictionaryType]
  /// - `Map` fields with identical key sets become [BjdataSoaObjectType]
  /// - `List` fields of identical, non-zero length become [BjdataSoaArrayType]
  ///
  /// Returns null for anything else, including records with differing key sets,
  /// fields that are null in some records but set in others, fields mixing `int`
  /// and `double`, and fields holding [TypedData].
  static BjdataSoaSchema? tryInfer(List<Map<String, Object?>> records, [int depth = 0]) {
    if (records.isEmpty || depth > _maxSoaDepth) return null;

    final names = records.first.keys.toList(growable: false);
    if (names.isEmpty) return null;
    for (final record in records) {
      if (record.length != names.length) return null;
      for (final name in names) {
        if (!record.containsKey(name)) return null;
      }
    }

    final fields = <String, BjdataSoaType>{};
    for (final name in names) {
      final type = _tryInferType([for (final record in records) record[name]], depth + 1);
      if (type == null) return null;
      fields[name] = type;
    }
    return BjdataSoaSchema(fields);
  }

  /// Categorises [values] from the first entry, then verifies the rest in the
  /// same pass, so each field costs one walk of the column and no more.
  static BjdataSoaType? _tryInferType(List<Object?> values, int depth) {
    // Records can reference themselves, which would otherwise recurse forever.
    // Giving up simply means the list is written as a plain array of objects,
    // where the encoder's own cycle detection reports the problem.
    if (depth > _maxSoaDepth) return null;
    final first = values.first;

    if (first == null) {
      for (final value in values) {
        if (value != null) return null;
      }
      return const BjdataSoaNullType();
    }

    if (first is bool) {
      for (final value in values) {
        if (value is! bool) return null;
      }
      return const BjdataSoaBooleanType();
    }

    // int and double are kept apart so that a whole number never comes back as
    // a double, which a shared float64 column would do.
    if (first is int) {
      var min = first;
      var max = first;
      for (final value in values) {
        if (value is! int) return null;
        if (value < min) min = value;
        if (value > max) max = value;
      }
      return BjdataSoaValueType(_integerMarker(min, max));
    }

    if (first is double) {
      for (final value in values) {
        if (value is! double) return null;
      }
      return BjdataSoaValueType(BjdataMarker.float64);
    }

    if (first is String) {
      final distinct = <String>{};
      var bufferLength = 0;
      for (final value in values) {
        if (value is! String) return null;
        distinct.add(value);
        bufferLength += utf8.encode(value).length;
      }
      if (distinct.length * 2 <= values.length) {
        return BjdataSoaDictionaryType(distinct.toList(growable: false));
      }
      return BjdataSoaOffsetType(_integerMarker(0, bufferLength));
    }

    if (first is BigInt) {
      final distinct = <BigInt>{};
      for (final value in values) {
        if (value is! BigInt) return null;
        distinct.add(value);
      }
      return BjdataSoaDictionaryType(distinct.toList(growable: false), huge: true);
    }

    // TypedData is a List, but a strongly-typed array round-trips it exactly
    // while a fixed SoA array would flatten it into a plain list of numbers.
    if (first is TypedData) return null;

    if (first is Map) {
      final keys = first.keys.toList(growable: false);
      if (keys.isEmpty || keys.any((key) => key is! String)) return null;
      for (final value in values) {
        if (value is! Map || value.length != keys.length) return null;
        for (final key in keys) {
          if (!value.containsKey(key)) return null;
        }
      }

      final fields = <String, BjdataSoaType>{};
      for (final key in keys) {
        final type = _tryInferType([for (final value in values) (value as Map)[key]], depth + 1);
        if (type == null) return null;
        fields['$key'] = type;
      }
      return BjdataSoaObjectType(fields);
    }

    if (first is List) {
      final length = first.length;
      if (length == 0) return null;
      for (final value in values) {
        if (value is! List || value is TypedData || value.length != length) return null;
      }

      final elements = <BjdataSoaType>[];
      for (var i = 0; i < length; i++) {
        final type = _tryInferType([for (final value in values) (value as List)[i]], depth + 1);
        if (type == null) return null;
        elements.add(type);
      }
      return BjdataSoaArrayType(elements);
    }

    return null;
  }

  static BjdataMarker _integerMarker(int min, int max) => switch ((min, max)) {
        (>= 0, <= 255) => BjdataMarker.uint8,
        (>= -128, <= 127) => BjdataMarker.int8,
        (>= 0, <= 65535) => BjdataMarker.uint16,
        (>= -32768, <= 32767) => BjdataMarker.int16,
        (>= 0, <= 4294967295) => BjdataMarker.uint32,
        (>= -2147483648, <= 2147483647) => BjdataMarker.int32,
        (>= 0, _) => BjdataMarker.uint64,
        _ => BjdataMarker.int64,
      };

  @override
  bool operator ==(Object other) =>
      other is BjdataSoaSchema &&
      other.fields.length == fields.length &&
      fields.entries.every((e) => other.fields[e.key] == e.value);

  @override
  int get hashCode => Object.hash(Object.hashAll(fields.keys), Object.hashAll(fields.values));

  @override
  String toString() => 'BjdataSoaSchema($fields)';
}

/// A list that can be written as a Structure-of-Arrays container.
class BjdataSoaCandidate {
  BjdataSoaCandidate(this.schema, this.dimensions, this.records);

  /// The record structure shared by every record.
  final BjdataSoaSchema schema;

  /// The record grid, whose product is the length of [records].
  final List<int> dimensions;

  /// The records, flattened in row-major order.
  final List<Map<String, Object?>> records;
}

/// The fewest records that make a Structure-of-Arrays container worthwhile.
///
/// A single record needs a schema about as large as the object it replaces, so
/// it is never smaller than a plain array of objects.
const int _minimumSoaRecords = 2;

/// The deepest nesting examined while looking for a table.
///
/// Lists and records may reference themselves, so the search has to be bounded.
/// Anything deeper is treated as not being a table, which leaves it to the
/// ordinary encoder and its cycle detection.
const int _maxSoaDepth = 64;

/// Describes [list] as a Structure-of-Arrays container, or returns null if it is
/// not a uniform table of records.
///
/// Accepts a flat list of records, and, when [multiDimensional] is true,
/// rectangular nested lists of records for N-dimensional containers, where the
/// nesting becomes the container dimensions and the records are flattened in
/// row-major order.
///
/// With [multiDimensional] false a nested list is not a candidate, so it is
/// written as a nested array whose own elements may each still be packed.
BjdataSoaCandidate? tryBjdataSoaCandidate(List<Object?> list, {bool multiDimensional = true}) {
  final shape = _tryShape(list, 0, multiDimensional);
  if (shape == null) return null;
  if (shape.records.length < _minimumSoaRecords) return null;

  final schema = BjdataSoaSchema.tryInfer(shape.records);
  if (schema == null) return null;
  return BjdataSoaCandidate(schema, shape.dimensions, shape.records);
}

/// The dimensions and flattened records of [list], or null if the nesting is
/// ragged or the leaves are not all string-keyed maps.
({List<int> dimensions, List<Map<String, Object?>> records})? _tryShape(
  List<Object?> list,
  int depth,
  bool multiDimensional,
) {
  if (list.isEmpty || list is TypedData || depth > _maxSoaDepth) return null;
  final first = list.first;

  if (first is Map) {
    final records = <Map<String, Object?>>[];
    for (final element in list) {
      // Almost every map reaching here is already string-keyed, including the
      // Map<String, dynamic> that jsonDecode produces, so the type test settles
      // it without walking the keys.
      if (element is Map<String, Object?>) {
        records.add(element);
      } else if (element is Map && !element.keys.any((key) => key is! String)) {
        records.add(element.cast<String, Object?>());
      } else {
        return null;
      }
    }
    return (dimensions: [list.length], records: records);
  }

  if (multiDimensional && first is List && first is! TypedData) {
    List<int>? innerDimensions;
    final records = <Map<String, Object?>>[];
    for (final element in list) {
      if (element is! List) return null;
      final shape = _tryShape(element, depth + 1, multiDimensional);
      if (shape == null) return null;
      if (innerDimensions == null) {
        innerDimensions = shape.dimensions;
      } else if (!_sameDimensions(innerDimensions, shape.dimensions)) {
        return null;
      }
      records.addAll(shape.records);
    }
    return (dimensions: [list.length, ...innerDimensions!], records: records);
  }

  return null;
}

bool _sameDimensions(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Nests [flat] into [dimensions], which is how an N-dimensional container is
/// presented once decoded.
///
/// Returns [flat] unchanged for one-dimensional containers.
List<Object?> reshapeBjdataSoa(List<Object?> flat, List<int> dimensions) {
  if (dimensions.length <= 1) return flat;

  final inner = dimensions.sublist(1);
  final stride = inner.fold(1, (a, b) => a * b);
  return [
    for (var i = 0; i < dimensions.first; i++) reshapeBjdataSoa(flat.sublist(i * stride, (i + 1) * stride), inner),
  ];
}
