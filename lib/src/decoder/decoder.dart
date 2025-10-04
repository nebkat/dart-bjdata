import 'dart:convert';

import 'sink.dart';

/// This class parses BJData strings and builds the corresponding objects.
///
/// A BJData input must be the BJData encoding of a single BJData value,
/// which can be a list or map containing other values.
///
/// Throws [FormatException] if the input is not valid BJData text.
///
/// Example:
/// ```dart
/// const BjdataDecoder decoder = BjdataDecoder();
///
/// const Uint8List bjdataString = ...;
/// // 7b2369026904646174615b2369027b23
/// // 6902690474657874536903666f6f6905
/// // 76616c756569017b2369026904746578
/// // 74536903626172690576616c75656902
/// // 69047465787453690444617274
///
/// final Map<String, dynamic> object = decoder.convert(bjdataString);
///
/// final item = object['data'][0];
/// print(item['text']); // foo
/// print(item['value']); // 1
///
/// print(object['text']); // Dart
/// ```
///
/// Does not currently support chunked decoding.
final class BjdataDecoder extends Converter<List<int>, Object?> {
  final Object? Function(Object? key, Object? value)? _reviver;

  /// Constructs a new BjdataDecoder.
  ///
  /// The [reviver] may be `null`.
  const BjdataDecoder([Object? Function(Object? key, Object? value)? reviver]) : _reviver = reviver;

  /// Converts the given BJData-string [input] to its corresponding object.
  ///
  /// Parsed BJData values are of the types [num], [String], [bool], [Null],
  /// [List]s of parsed BJData values or [Map]s from [String] to parsed BJData
  /// values.
  ///
  /// If `this` was initialized with a reviver, then the parsing operation
  /// invokes the reviver on every object or list property that has been parsed.
  /// The arguments are the property name ([String]) or list index ([int]), and
  /// the value is the parsed value. The return value of the reviver is used as
  /// the value of that property instead the parsed value.
  ///
  /// Throws [FormatException] if the input is not valid BJData text.
  @override
  dynamic convert(List<int> input) => BjdataReader(_reviver).read(input);

  /// Starts a conversion from a chunked BJData string to its corresponding object.
  ///
  /// The output [sink] receives exactly one decoded element through `add`.
  // @override
  // ByteConversionSink startChunkedConversion(Sink<Object?> sink) =>
  //     DecoderSink(_reviver, sink);
}
