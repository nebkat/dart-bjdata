import 'dart:convert';
import 'dart:typed_data';

import 'sink.dart';

/// Encoder that encodes a single object as a BJData buffer.
final class BjdataEncoder extends Converter<Object?, List<int>> {
  /// Default buffer size used by the BJData encoder.
  static const int _defaultBufferSize = 256;

  /// Function called with each un-encodable object encountered.
  final Object? Function(dynamic)? _toEncodable;

  /// Output buffer size.
  final int _bufferSize;

  /// Create converter.
  ///
  /// The [bufferSize] is the size of the internal buffers used to collect
  /// bytes.
  /// If using [startChunkedConversion], it will be the size of the chunks.
  ///
  /// The BJData encoder handles numbers, strings, booleans, null, lists and maps
  /// directly.
  ///
  /// Any other object is attempted converted by [toEncodable] to an object that
  /// is of one of the convertible types.
  ///
  /// If [toEncodable] is omitted, it defaults to calling `.toJson()` on the
  /// object.
  BjdataEncoder([
    dynamic Function(dynamic object)? toEncodable,
    int? bufferSize,
  ])  : _toEncodable = toEncodable,
        _bufferSize = bufferSize ?? _defaultBufferSize;

  /// Converts [object] to a BJData [List<int>] buffer.
  ///
  /// Directly serializable values are [num], [String], [bool], and [Null], as
  /// well as some [List] and [Map] values. For [List], the elements must all be
  /// serializable. For [Map], the keys must be [String] and the values must be
  /// serializable.
  ///
  /// If a value of any other type is attempted to be serialized, the
  /// `toEncodable` function provided in the constructor is called with the value
  /// as argument. The result, which must be a directly serializable value, is
  /// serialized instead of the original value.
  ///
  /// If the conversion throws, or returns a value that is not directly
  /// serializable, a [BjdataUnsupportedObjectError] exception is thrown.
  /// If the call throws, the error is caught and stored in the
  /// [BjdataUnsupportedObjectError]'s `cause` field.
  ///
  /// If a [List] or [Map] contains a reference to itself, directly or through
  /// other lists or maps, it cannot be serialized and a [BjdataCyclicError] is
  /// thrown.
  ///
  /// [object] should not change during serialization.
  ///
  /// If an object is serialized more than once, [convert] may cache the text
  /// for it. In other words, if the content of an object changes after it is
  /// first serialized, the new values may not be reflected in the result.
  @override
  List<int> convert(Object? object) {
    BytesBuilder builder = BytesBuilder(copy: false);
    BjdataBufferWriter.encode(
      object,
      _toEncodable,
      _bufferSize,
      (chunk) => builder.add(chunk),
    );
    return builder.takeBytes();
  }

  /// Start a chunked conversion.
  ///
  /// Only one object can be passed into the returned sink.
  ///
  /// The argument [sink] will receive byte lists in sizes depending on the
  /// `bufferSize` passed to the constructor when creating this encoder.
  @override
  ChunkedConversionSink<Object?> startChunkedConversion(Sink<List<int>> sink) {
    ByteConversionSink byteSink;
    if (sink is ByteConversionSink) {
      byteSink = sink;
    } else {
      byteSink = ByteConversionSink.from(sink);
    }
    return BjdataEncoderSink(byteSink, _toEncodable, _bufferSize);
  }
}

/// Encoder that encodes a single object as a BJData block notation string.
final class BjdataBlockNotationEncoder extends Converter<Object?, String> {
  /// The string used for indention.
  ///
  /// When generating multi-line output, this string is inserted once at the
  /// beginning of each indented line for each level of indentation.
  ///
  /// If `null`, the output is encoded as a single line.
  final String? indent;

  /// Function called with each un-encodable object encountered.
  final Object? Function(dynamic)? _toEncodable;

  /// Creates a BJData block notation converter.
  ///
  /// The BJData encoder handles numbers, strings, booleans, null, lists and maps
  /// directly.
  ///
  /// Any other object is attempted converted by [toEncodable] to an object that
  /// is of one of the convertible types.
  ///
  /// If [toEncodable] is omitted, it defaults to calling `.toJson()` on the
  /// object.
  const BjdataBlockNotationEncoder([this._toEncodable]) : indent = null;

  /// Creates a BJData block notation converter that creates multi-line output.
  ///
  /// The encoding of elements of lists and maps are indented and put on separate
  /// lines. The [indent] string is prepended to these elements, once for each
  /// level of indentation.
  ///
  /// If [indent] is `null`, the output is encoded as a single line.
  ///
  /// The BJData encoder handles numbers, strings, booleans, null, lists and maps
  /// directly.
  ///
  /// Any other object is attempted converted by [toEncodable] to an object that
  /// is of one of the convertible types.
  ///
  /// If [toEncodable] is omitted, it defaults to calling `.toJson()` on the
  /// object.
  const BjdataBlockNotationEncoder.withIndent(this.indent, [this._toEncodable]);

  /// Converts [object] to a BJData block notation [String].
  ///
  /// Directly serializable values are [num], [String], [bool], and [Null], as
  /// well as some [List] and [Map] values. For [List], the elements must all be
  /// serializable. For [Map], the keys must be [String] and the values must be
  /// serializable.
  ///
  /// If a value of any other type is attempted to be serialized, the
  /// `toEncodable` function provided in the constructor is called with the value
  /// as argument. The result, which must be a directly serializable value, is
  /// serialized instead of the original value.
  ///
  /// If the conversion throws, or returns a value that is not directly
  /// serializable, a [BjdataUnsupportedObjectError] exception is thrown.
  /// If the call throws, the error is caught and stored in the
  /// [BjdataUnsupportedObjectError]'s `cause` field.
  ///
  /// If a [List] or [Map] contains a reference to itself, directly or through
  /// other lists or maps, it cannot be serialized and a [BjdataCyclicError] is
  /// thrown.
  ///
  /// [object] should not change during serialization.
  ///
  /// If an object is serialized more than once, [convert] may cache the text
  /// for it. In other words, if the content of an object changes after it is
  /// first serialized, the new values may not be reflected in the result.
  @override
  String convert(Object? object) => BjdataBlockNotationStringifier.stringify(object, _toEncodable, indent);

  /// Starts a chunked conversion.
  ///
  /// The converter works more efficiently if the given [sink] is a
  /// [StringConversionSink].
  ///
  /// Returns a chunked-conversion sink that accepts at most one object. It is
  /// an error to invoke `add` more than once on the returned sink.
  @override
  ChunkedConversionSink<Object?> startChunkedConversion(Sink<String> sink) {
    return BjdataBlockNotationEncoderSink(
      sink is StringConversionSink ? sink : StringConversionSink.from(sink),
      _toEncodable,
      indent,
    );
  }
}
