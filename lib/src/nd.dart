import 'dart:typed_data';

import 'marker.dart';
import 'packing.dart';

/// The strong type marker for [buffer], or null if it is not a kind of typed
/// data BJData can store.
BjdataMarker? bjdataTypedDataMarker(TypedData buffer) => switch (buffer) {
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
      _ => null,
    };

/// The number of elements in [buffer].
int bjdataTypedDataLength(TypedData buffer) => buffer.lengthInBytes ~/ buffer.elementSizeInBytes;

/// A nested list that can be written as an N-dimensional optimized array.
class BjdataNdCandidate {
  BjdataNdCandidate(this.marker, this.dimensions, this.rows);

  /// The strong type shared by every element.
  final BjdataMarker marker;

  /// The array shape, outermost axis first.
  final List<int> dimensions;

  /// The innermost axis of the nesting, in row-major order.
  ///
  /// Concatenating these gives the payload.
  final List<TypedData> rows;
}

/// The fewest rows that make an N-dimensional array worth writing.
///
/// One row needs a dimension array to say what a plain count already says, so
/// it comes out larger than simply nesting the row in an array.
const int _minimumNdRows = 2;

/// The deepest nesting examined while looking for an array.
///
/// Lists may reference themselves, so the search has to be bounded. Anything
/// deeper is treated as not being an N-dimensional array, which leaves it to the
/// ordinary encoder and its cycle detection.
const int _maxNdDepth = 64;

/// Describes [list] as an N-dimensional optimized array, or returns null if it
/// is not a rectangular nesting of same-typed rows.
///
/// Only typed data qualifies, matching how a flat list is written: a
/// [Float64List] becomes an optimized array while a `List<double>` does not, so
/// a `List<Float64List>` becomes an N-dimensional array while a
/// `List<List<double>>` stays a nested array.
BjdataNdCandidate? tryBjdataNdCandidate(List<Object?> list, {bool compactTypes = true}) {
  final shape = _tryShape(list, 0);
  if (shape == null || shape.rows.length < _minimumNdRows) return null;

  var marker = shape.marker;
  if (compactTypes) {
    // Narrow across every row at once, so the array keeps one type throughout.
    final narrowed = _narrowestMarker(shape.rows);
    if (narrowed != null && narrowed.fixedByteLength! < marker.fixedByteLength!) marker = narrowed;
  }
  return BjdataNdCandidate(marker, shape.dimensions, shape.rows);
}

/// The narrowest strong type holding every value of every row unchanged.
BjdataMarker? _narrowestMarker(List<TypedData> rows) {
  if (rows.first is Float32List || rows.first is Float64List) {
    return bjdataFloatMarker([for (final row in rows) ...(row as List<double>)]);
  }
  if (rows.first is ByteData) return null;

  var min = 0;
  var max = 0;
  for (final row in rows) {
    for (final value in row as List<int>) {
      if (value < min) min = value;
      if (value > max) max = value;
    }
  }
  return bjdataIntegerMarker(min, max);
}

({BjdataMarker marker, List<int> dimensions, List<TypedData> rows})? _tryShape(List<Object?> list, int depth) {
  if (list.isEmpty || list is TypedData || depth > _maxNdDepth) return null;
  final first = list.first;

  // The innermost axis: every element is typed data of one type and length.
  if (first is TypedData) {
    final marker = bjdataTypedDataMarker(first);
    if (marker == null) return null;
    final length = bjdataTypedDataLength(first);
    if (length == 0) return null;

    final rows = <TypedData>[];
    for (final element in list) {
      if (element is! TypedData ||
          bjdataTypedDataMarker(element) != marker ||
          bjdataTypedDataLength(element) != length) {
        return null;
      }
      rows.add(element);
    }
    return (marker: marker, dimensions: [list.length, length], rows: rows);
  }

  if (first is List) {
    BjdataMarker? marker;
    List<int>? innerDimensions;
    final rows = <TypedData>[];
    for (final element in list) {
      if (element is! List) return null;
      final shape = _tryShape(element, depth + 1);
      if (shape == null) return null;
      if (marker == null) {
        marker = shape.marker;
        innerDimensions = shape.dimensions;
      } else if (marker != shape.marker || !_sameDimensions(innerDimensions!, shape.dimensions)) {
        return null;
      }
      rows.addAll(shape.rows);
    }
    return (marker: marker!, dimensions: [list.length, ...innerDimensions!], rows: rows);
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
