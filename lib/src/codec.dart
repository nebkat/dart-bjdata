import 'dart:convert';

import 'decoder/decoder.dart';
import 'encoder/encoder.dart';

const BjdataCodec bjdata = BjdataCodec();

class BjdataCodec extends Codec<Object?, List<int>> {
  final Object? Function(Object? key, Object? value)? _reviver;
  final Object? Function(dynamic)? _toEncodable;

  const BjdataCodec({
    Object? Function(Object? key, Object? value)? reviver,
    Object? Function(dynamic object)? toEncodable,
  })  : _reviver = reviver,
        _toEncodable = toEncodable;

  BjdataCodec.withReviver(dynamic Function(Object? key, Object? value) reviver)
      : this(reviver: reviver);

  @override
  dynamic decode(
    List<int> encoded, {
    Object? Function(Object? key, Object? value)? reviver,
  }) {
    reviver ??= _reviver;
    if (reviver == null) return decoder.convert(encoded);
    return BjdataDecoder(reviver).convert(encoded);
  }

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

List<int> bjdataEncode(
  Object? object, {
  Object? Function(Object? nonEncodable)? toEncodable,
}) =>
    bjdata.encode(object, toEncodable: toEncodable);

dynamic bjdataDecode(
  List<int> source, {
  Object? Function(Object? key, Object? value)? reviver,
}) =>
    bjdata.decode(source, reviver: reviver);
