import 'dart:convert';
import 'dart:typed_data';

import 'sink.dart';

/// Encoder that encodes a single object as a UTF-8 encoded BJDATA string.
///
/// This encoder works equivalently to first converting the object to
/// a BJDATA string, and then UTF-8 encoding the string, but without
/// creating an intermediate string.
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
  /// The BJDATA encoder handles numbers, strings, booleans, null, lists and maps
  /// directly.
  ///
  /// Any other object is attempted converted by [toEncodable] to an object that
  /// is of one of the convertible types.
  ///
  /// If [toEncodable] is omitted, it defaults to calling `.toBjdata()` on the
  /// object.
  BjdataEncoder([
    dynamic Function(dynamic object)? toEncodable,
    int? bufferSize,
  ])  : _toEncodable = toEncodable,
        _bufferSize = bufferSize ?? _defaultBufferSize;

  /// Convert [object] into encoded BJData.
  @override
  List<int> convert(Object? object) {
    BytesBuilder builder = BytesBuilder(copy: false);
    ByteEncoder.encode(
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
    return EncoderSink(byteSink, _toEncodable, _bufferSize);
  }
}
