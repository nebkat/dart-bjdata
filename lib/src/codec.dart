import 'dart:convert';

import 'decoder/decoder.dart';
import 'encoder/encoder.dart';

const BjdataCodec bjdata = BjdataCodec();

/// A [BjdataCodec] encodes objects to BJData and decodes BJData to
/// objects.
///
/// Examples:
/// ```dart
/// var encoded = bjdata.encode([1, 2, { "a": null }]);
/// var decoded = bjdata.decode(listIntFromHex('5b550155027b5501615a7d5d'));
/// ```
class BjdataCodec extends Codec<Object?, List<int>> {
  final Object? Function(Object? key, Object? value)? _reviver;
  final Object? Function(dynamic)? _toEncodable;

  /// Creates a `BjdataCodec` with the given reviver and encoding function.
  ///
  /// The [reviver] function is called during decoding. It is invoked once for
  /// each object or list property that has been parsed.
  /// The `key` argument is either the integer list index for a list property,
  /// the string map key for object properties, or `null` for the final result.
  ///
  /// If [reviver] is omitted, it defaults to returning the value argument.
  ///
  /// The [toEncodable] function is used during encoding. It is invoked for
  /// values that are not directly encodable to BJData (a value that is not a
  /// number, boolean, string, null, list or a map with string keys). The
  /// function must return an object that is directly encodable. The elements of
  /// a returned list and values of a returned map do not need to be directly
  /// encodable, and if they aren't, `toEncodable` will be used on them as well.
  /// Please notice that it is possible to cause an infinite recursive regress
  /// in this way, by effectively creating an infinite data structure through
  /// repeated call to `toEncodable`.
  ///
  /// If [toEncodable] is omitted, it defaults to a function that returns the
  /// result of calling `.toJson()` on the unencodable object.
  const BjdataCodec({
    Object? Function(Object? key, Object? value)? reviver,
    Object? Function(dynamic object)? toEncodable,
  })  : _reviver = reviver,
        _toEncodable = toEncodable;

  /// Creates a `BjdataCodec` with the given reviver.
  ///
  /// The [reviver] function is called once for each object or list property
  /// that has been parsed during decoding. The `key` argument is either the
  /// integer list index for a list property, the string map key for object
  /// properties, or `null` for the final result.
  BjdataCodec.withReviver(dynamic Function(Object? key, Object? value) reviver) : this(reviver: reviver);

  /// Decodes the buffer and returns the resulting BJData object.
  ///
  /// The optional [reviver] function is called once for each object or list
  /// property that has been parsed during decoding. The `key` argument is either
  /// the integer list index for a list property, the string map key for object
  /// properties, or `null` for the final result.
  ///
  /// The default [reviver] (when not provided) is the identity function.
  @override
  dynamic decode(
    List<int> encoded, {
    Object? Function(Object? key, Object? value)? reviver,
  }) {
    reviver ??= _reviver;
    if (reviver == null) return decoder.convert(encoded);
    return BjdataDecoder(reviver).convert(encoded);
  }

  /// Converts [value] to a BJData buffer.
  ///
  /// If value contains objects that are not directly encodable to BJData
  /// (a value that is not a number, boolean, string, null, list or a map
  /// with string keys), the [toEncodable] function is used to convert it to an
  /// object that must be directly encodable.
  ///
  /// If [toEncodable] is omitted, it defaults to a function that returns the
  /// result of calling `.toJson()` on the unencodable object.
  @override
  List<int> encode(
    Object? input, {
    Object? Function(dynamic object)? toEncodable,
  }) {
    toEncodable ??= _toEncodable;
    if (toEncodable == null) return encoder.convert(input);
    return BjdataEncoder(toEncodable).convert(input);
  }

  @override
  BjdataEncoder get encoder {
    if (_toEncodable == null) return BjdataEncoder();
    return BjdataEncoder(_toEncodable);
  }

  @override
  BjdataDecoder get decoder {
    if (_reviver == null) return const BjdataDecoder();
    return BjdataDecoder(_reviver);
  }
}

/// Converts [object] into BJData.
///
/// See [BjdataCodec.encode]
List<int> bjdataEncode(
  Object? object, {
  Object? Function(Object? nonEncodable)? toEncodable,
}) =>
    bjdata.encode(object, toEncodable: toEncodable);

/// Parses the BJData [source] and returns the resulting object.
///
/// See [BjdataCodec.decode]
dynamic bjdataDecode(
  List<int> source, {
  Object? Function(Object? key, Object? value)? reviver,
}) =>
    bjdata.decode(source, reviver: reviver);

/// Converts [object] into a BJData block notation string.
///
/// See [BjdataBlockNotationEncoder]
String bjdataBlockNotation(
  Object? object, {
  Object? Function(Object? nonEncodable)? toEncodable,
  String? indent,
}) =>
    BjdataBlockNotationEncoder.withIndent(indent, toEncodable).convert(object);
