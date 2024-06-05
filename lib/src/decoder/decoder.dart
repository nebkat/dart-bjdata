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
/// const String bjdataString = '''
///   {
///     "data": [{"text": "foo", "value": 1 },
///              {"text": "bar", "value": 2 }],
///     "text": "Dart"
///   }
/// ''';
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
/// When used as a [StreamTransformer], the input stream may emit
/// multiple strings. The concatenation of all of these strings must
/// be a valid BJData encoding of a single BJData value.
final class BjdataDecoder extends Converter<List<int>, Object?> {
  final Object? Function(Object? key, Object? value)? _reviver;

  /// Constructs a new BjdataDecoder.
  ///
  /// The [reviver] may be `null`.
  const BjdataDecoder([Object? Function(Object? key, Object? value)? reviver])
      : _reviver = reviver;

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
  dynamic convert(List<int> input) => Decoder().parse(input);

  /// Starts a conversion from a chunked BJData string to its corresponding object.
  ///
  /// The output [sink] receives exactly one decoded element through `add`.
  // @override
  // ByteConversionSink startChunkedConversion(Sink<Object?> sink) =>
  //     DecoderSink(_reviver, sink);
}
