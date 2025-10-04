import 'dart:math';
import 'dart:typed_data';

import 'package:bjdata/bjdata.dart';
import 'package:bjdata/src/marker.dart';
import 'package:test/test.dart';

extension on List<int> {
  String get hex => map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

extension on String {
  List<int> get bytes => fromHexString(this);
}

Uint8List fromHexString(String hex) {
  final length = hex.length;
  final bytes = Uint8List((length / 2).ceil());
  for (var i = 0; i < length; i += 2) {
    final byte = hex.substring(i, i + 2 > length ? length : i + 2);
    bytes[i ~/ 2] = int.parse(byte, radix: 16);
  }
  return bytes;
}

String toHexString(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

typedef M = BjdataMarker;

void main() {
  group('primitives', () {
    final bidirectional = [
      ((null), 'Z', null, '5a'),
      ((bool), 'T', true, '54'),
      ((bool), 'F', false, '46'),
      ((int), 'U', 0, '5500'),
      ((int), 'U', 255, '55ff'),
      ((int), 'u', 256, '750001'),
      ((int), 'u', 65535, '75ffff'),
      ((int), 'm', 65536, '6d00000100'),
      ((int), 'm', 4294967295, '6dffffffff'),
      ((int), 'M', 4294967296, '4d0000000001000000'),
      if (1 is! double) ((int), 'M', int.parse('9223372036854775807'), '4dffffffffffffff7f'),
      ((int), 'i', -1, '69ff'),
      ((int), 'i', -128, '6980'),
      ((int), 'I', -129, '497fff'),
      ((int), 'I', -32768, '490080'),
      ((int), 'l', -32769, '6cff7fffff'),
      ((int), 'l', -2147483648, '6c00000080'),
      ((int), 'm', -2147483649, '4cffffff7fffffffff'),
      ((int), 'm', -9223372036854775808, '4c0000000000000080'),
      // ((int), 'M', 9223372036854775808, '4d0000000000000080'),
      // ((int), 'M', 18446744073709551615, '4dffffffffffffffff'),
      ((double), 'D', double.infinity, '44000000000000f07f'),
      ((double), 'D', double.negativeInfinity, '44000000000000f0ff'),
      if (1 is! double) ((double), 'D', 0.0, '440000000000000000'),
      if (1 is! double) ((double), 'D', -0.0, '440000000000000080'),
      if (1 is! double) ((double), 'D', 1.0, '44000000000000f03f'),
      if (1 is! double) ((double), 'D', -1.0, '44000000000000f0bf'),
      ((double), 'D', pi, '44182d4454fb210940'),
      ((String), 'S', '', '535500'),
      ((String), 'S', 'hello', '53550568656c6c6f'),
      ((BigInt), 'H', BigInt.zero, '48550130'),
      ((BigInt), 'H', BigInt.one, '48550131'),
      ((BigInt), 'H', -BigInt.one, '4855022d31'),
      ((BigInt), 'H', BigInt.parse('9999999999999999999'), '48551339393939393939393939393939393939393939'),
      ((BigInt), 'H', BigInt.parse('-9999999999999999999'), '4855142d39393939393939393939393939393939393939'),
    ];

    final decodes = [
      ((int), 'U', '5500', 0),
      ((int), 'U', '55ff', 255),
      ((int), 'u', '750000', 0),
      ((int), 'u', '75ffff', 65535),
      ((int), 'm', '6d00000000', 0),
      ((int), 'm', '6dffffffff', 4294967295),
      ((int), 'M', '4d0000000000000000', 0),
      if (1 is! double) ((int), 'M', '4dffffffffffffff7f', int.parse('9223372036854775807')),
      // ((int), 'M', '4d0000000000000080', -9223372036854775808),
      ((int), 'i', '6900', 0),
      ((int), 'i', '69ff', -1),
      ((int), 'i', '697f', 127),
      ((int), 'i', '6980', -128),
      ((int), 'I', '490000', 0),
      ((int), 'I', '49ffff', -1),
      ((int), 'I', '49ff7f', 32767),
      ((int), 'I', '490080', -32768),
      ((int), 'l', '6c00000000', 0),
      ((int), 'l', '6cffffffff', -1),
      ((int), 'l', '6cffffff7f', 2147483647),
      ((int), 'l', '6c00000080', -2147483648),
      ((int), 'L', '4c0000000000000000', 0),
      ((int), 'L', '4cffffffffffffffff', -1),
      if (1 is! double) ((int), 'L', '4cffffffffffffff7f', int.parse('9223372036854775807')),
      ((int), 'L', '4c0000000000000080', -9223372036854775808),
      ((double), 'h', '680000', 0.0),
      ((double), 'h', '680100', pow(2, -14) * (1 / 1024)),
      ((double), 'h', '68ff03', pow(2, -14) * (1023 / 1024)),
      ((double), 'h', '680004', pow(2, -14) * (1)),
      ((double), 'h', '68003c', 1.0),
      ((double), 'h', '68013c', pow(2, 0) * (1 + 1 / 1024)),
      ((double), 'h', '68ff7b', pow(2, 15) * (1 + 1023 / 1024)),
      ((double), 'h', '68007c', double.infinity),
      ((double), 'h', '6800fc', double.negativeInfinity),
      ((double), 'd', '440000000000000000', 0.0),
      ((double), 'd', '44000000000000f03f', 1.0),
      ((double), 'd', '44000000000000f0bf', -1.0),
      ((double), 'd', '44000000000000f07f', double.infinity),
      ((double), 'd', '44000000000000f0ff', double.negativeInfinity),
      ((String), 'C', '4361', 'a'),
      ((String), 'C', '4343', 'C'),
      ((BigInt), 'H', '4869022d30', BigInt.zero), // -0
    ];

    group('encode', () {
      for (final (type, marker, value, hex) in bidirectional) {
        test('encode $type/$marker $value', () {
          final encoded = bjdataEncode(value);
          expect(encoded.hex, hex);
        });
      }
    });

    group('decode', () {
      for (final (type, marker, value, hex) in bidirectional) {
        test('decode $type/$marker $value', () {
          final decoded = bjdataDecode(hex.bytes);
          expect(decoded, value);
        });
      }

      for (final (type, marker, hex, value) in decodes) {
        test('decode $type/$marker $value', () {
          final decoded = bjdataDecode(hex.bytes);
          expect(decoded, value);
        });
      }
    });
  });

  group('containers', () {
    group('array', () {
      final bidirectional = [
        ([], '5b5d'),
        ([1, 2, 3], '5b5501550255035d'),
        ([null, true, false], '5b5a54465d'),
        (['a', 'bc', 'def'], '5b5355016153550262635355036465665d'),
        ([null, true, false, 1, 'a'], '5b5a54465501535501615d'),
        ([[], [], []], '5b5b5d5b5d5b5d5d'),
        ([{}, {}, {}], '5b7b7d7b7d7b7d5d'),
      ];

      group('encode', () {
        for (final (value, hex) in bidirectional) {
          test('encode [] $value', () {
            final encoded = bjdataEncode(value);
            expect(encoded.hex, hex);
          });
        }
      });

      group('decode', () {
        for (final (value, hex) in bidirectional) {
          test('decode [] $value', () {
            final decoded = bjdataDecode(hex.bytes);
            expect(decoded, value);
          });
        }
      });

      test('noop', () {
        expect(bjdataDecode('5b4e5d'.bytes), []);
        expect(bjdataDecode('5b4e4e5d'.bytes), []);
        expect(bjdataDecode('5b55014e55024e4e4e55034e4e5d'.bytes), [1, 2, 3]);
        expect(bjdataDecode('5b23550355014e55024e4e5503'.bytes), [1, 2, 3]);
      });
    });

    group('strong array', () {
      final empty = ByteData(0);
      final nonEmpty = ByteData(8)
        ..setUint32(0, 0xaabbccdd, Endian.little)
        ..setUint32(4, 0x11223344, Endian.little);
      final bidirectional = [
        ((ByteData), '[\$B', ByteData.sublistView(empty), '5b2442235500'),
        ((ByteData), '[\$B', ByteData.sublistView(nonEmpty), '5b2442235508ddccbbaa44332211'),
        ((Uint8List), '[\$U', Uint8List.sublistView(empty), '5b2455235500'),
        ((Uint8List), '[\$U', Uint8List.sublistView(nonEmpty), '5b2455235508ddccbbaa44332211'),
        ((Int8List), '[\$i', Int8List.sublistView(empty), '5b2469235500'),
        ((Int8List), '[\$i', Int8List.sublistView(nonEmpty), '5b2469235508ddccbbaa44332211'),
        ((Uint16List), '[\$u', Uint16List.sublistView(empty), '5b2475235500'),
        ((Uint16List), '[\$u', Uint16List.sublistView(nonEmpty), '5b2475235504ddccbbaa44332211'),
        ((Int16List), '[\$I', Int16List.sublistView(empty), '5b2449235500'),
        ((Int16List), '[\$I', Int16List.sublistView(nonEmpty), '5b2449235504ddccbbaa44332211'),
        ((Uint32List), '[\$m', Uint32List.sublistView(empty), '5b246d235500'),
        ((Uint32List), '[\$m', Uint32List.sublistView(nonEmpty), '5b246d235502ddccbbaa44332211'),
        ((Int32List), '[\$l', Int32List.sublistView(empty), '5b246c235500'),
        ((Int32List), '[\$l', Int32List.sublistView(nonEmpty), '5b246c235502ddccbbaa44332211'),
        if (1 is! double) ((Uint64List), '[\$M', Uint64List.sublistView(empty), '5b244d235500'),
        if (1 is! double) ((Uint64List), '[\$M', Uint64List.sublistView(nonEmpty), '5b244d235501ddccbbaa44332211'),
        if (1 is! double) ((Int64List), '[\$L', Int64List.sublistView(empty), '5b244c235500'),
        if (1 is! double) ((Int64List), '[\$L', Int64List.sublistView(nonEmpty), '5b244c235501ddccbbaa44332211'),
        ((Float32List), '[\$B', Float32List.sublistView(empty), '5b2464235500'),
        ((Float32List), '[\$B', Float32List.sublistView(nonEmpty), '5b2464235502ddccbbaa44332211'),
        ((Float64List), '[\$B', Float64List.sublistView(empty), '5b2444235500'),
        ((Float64List), '[\$B', Float64List.sublistView(nonEmpty), '5b2444235501ddccbbaa44332211'),
      ];

      group('encode', () {
        for (final (type, marker, value, hex) in bidirectional) {
          test('encode $type/$marker $value', () {
            final encoded = bjdataEncode(value);
            expect(encoded.hex, hex);
          });
        }
      });

      group('decode', () {
        for (final (type, marker, value, hex) in bidirectional) {
          test('decode $type/$marker $value', () {
            final decoded = bjdataDecode(hex.bytes);
            expect(decoded.runtimeType, value.runtimeType);
            expect(decoded.buffer.asUint8List(), value.buffer.asUint8List());
          });
        }
      });

      group('invalid', () {
        test('type', () {
          List<int> emptyStrongTypeOf(M m) => [
                M.arrayOpen.i,
                M.strongType.i,
                m.i,
                M.count.i,
                0,
                M.arrayClose.i,
              ];

          for (final m in BjdataMarker.values) {
            if (m.isValidStrongType) continue;
            expect(() => bjdataDecode(emptyStrongTypeOf(m)), throwsA(isA<FormatException>()));
          }
        });

        test('missing count', () {
          expect(
            () => bjdataDecode([M.arrayOpen.i, M.strongType.i, M.uint8.i, M.arrayClose.i]),
            throwsA(isA<FormatException>()),
          );
        });

        test('invalid count', () {
          expect(
            () => bjdataDecode([M.arrayOpen.i, M.strongType.i, M.uint8.i, M.count.i, M.null_.i]),
            throwsA(isA<FormatException>()),
          );
        });
      });
    });

    group('object', () {
      final bidirectional = [
        ({}, '7b7d'),
        ({'a': 1, 'b': 2, 'c': 3}, '7b5501615501550162550255016355037d'),
        ({'a': null, 'b': true, 'c': false}, '7b5501615a55016254550163467d'),
        ({'a': 'a', 'b': 'bc', 'c': 'def'}, '7b5501615355016155016253550262635501635355036465667d'),
        ({'a': null, 'b': 1, 'c': true}, '7b5501615a5501625501550163547d'),
        ({'a': [], 'b': [], 'c': []}, '7b5501615b5d5501625b5d5501635b5d7d'),
        ({'a': {}, 'b': {}, 'c': {}}, '7b5501617b7d5501627b7d5501637b7d7d'),
      ];

      group('encode', () {
        for (final (value, hex) in bidirectional) {
          test('encode {} $value', () {
            final encoded = bjdataEncode(value);
            expect(encoded.hex, hex);
          });
        }
      });

      group('decode', () {
        for (final (value, hex) in bidirectional) {
          test('decode {} $value', () {
            final decoded = bjdataDecode(hex.bytes);
            expect(decoded, value);
          });
        }
      });

      test('noop', () {
        expect(bjdataDecode('7b4e7d'.bytes), {});
        expect(bjdataDecode('7b4e4e7d'.bytes), {});
        expect(bjdataDecode('7b4e55016155014e55016255024e4e4e55016355034e4e7d'.bytes), {'a': 1, 'b': 2, 'c': 3});
        expect(bjdataDecode('7b2355034e55016155014e4e4e55016255024e5501635503'.bytes), {'a': 1, 'b': 2, 'c': 3});
      });
    });

    group('cyclic check', () {
      test('list cycle', () {
        final list = [];
        list.add(list);
        expect(() => bjdataEncode(list), throwsA(isA<BjdataCyclicError>()));
      });

      test('map cycle', () {
        final map = {};
        map['self'] = map;
        expect(() => bjdataEncode(map), throwsA(isA<BjdataCyclicError>()));
      });

      test('list map cycle', () {
        final list = [];
        list.add({'list': list});
        expect(() => bjdataEncode(list), throwsA(isA<BjdataCyclicError>()));
      });

      test('map list cycle', () {
        final map = {};
        map['list'] = [map];
        expect(() => bjdataEncode(map), throwsA(isA<BjdataCyclicError>()));
      });
    });
  });

  group('invalid', () {
    test('empty', () {
      expect(() => bjdataDecode([]), throwsA(isA<FormatException>()));
    });

    test('extra data', () {
      final entries = [
        [M.true_.i, M.true_.i],
        [
          M.arrayOpen.i,
          M.arrayClose.i,
          M.true_.i,
        ],
        [
          M.arrayOpen.i,
          M.count.i,
          M.uint8.i,
          0,
          M.true_.i,
        ],
        [
          M.arrayOpen.i,
          M.count.i,
          M.uint8.i,
          0,
          M.noop.i,
        ],
      ];
      for (final entry in entries) {
        expect(() => bjdataDecode(entry), throwsA(isA<FormatException>()));
      }
    });

    test('unexpected marker', () {
      final entries = [
        0x00,
        M.arrayClose.i,
        M.objectClose.i,
        M.strongType.i,
        M.count.i,
        M.noop.i,
      ];
      for (final entry in entries) {
        expect(() => bjdataDecode([entry]), throwsA(isA<FormatException>()));
      }
    });
  });
}
