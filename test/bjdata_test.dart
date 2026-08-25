import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:bjdata/bjdata.dart';
import 'package:bjdata/src/encoder/sink.dart';
import 'package:bjdata/src/marker.dart';
import 'package:bjdata/src/soa.dart';
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

      group('n-dimensional array', () {
        // The 2x3x4 uint8 array from the specification's worked example.
        const expected = [
          [
            [1, 9, 6, 0],
            [2, 9, 3, 1],
            [8, 0, 9, 6],
          ],
          [
            [6, 4, 2, 7],
            [8, 5, 1, 2],
            [3, 3, 2, 6],
          ],
        ];
        const rowMajorData = [1, 9, 6, 0, 2, 9, 3, 1, 8, 0, 9, 6, 6, 4, 2, 7, 8, 5, 1, 2, 3, 3, 2, 6];
        const columnMajorData = [1, 6, 2, 8, 8, 3, 9, 4, 9, 5, 0, 3, 6, 2, 3, 1, 9, 2, 0, 7, 1, 2, 6, 6];

        /// `[$U#` followed by [count], the dimension array and the payload.
        List<int> uint8Array(List<int> count, List<int> data) => [
              M.arrayOpen.i, M.strongType.i, M.uint8.i, M.count.i, //
              ...count,
              ...data,
            ];

        /// An optimized dimension array, `[$U#<n>` with no closing bracket.
        List<int> optimizedDims(List<int> dimensions) => [
              M.arrayOpen.i, M.strongType.i, M.uint8.i, M.count.i, M.uint8.i, dimensions.length, //
              ...dimensions,
            ];

        /// A plain dimension array, each entry with its own marker.
        List<int> plainDims(List<int> dimensions) => [
              M.arrayOpen.i, //
              for (final dimension in dimensions) ...[M.uint8.i, dimension],
              M.arrayClose.i,
            ];

        test('decodes the specification example in row-major order', () {
          expect(bjdataDecode(uint8Array(optimizedDims([2, 3, 4]), rowMajorData)), expected);
        });

        test('decodes the specification example in column-major order', () {
          // The dimension array wrapped in a single element array.
          final count = [
            M.arrayOpen.i,
            ...optimizedDims([2, 3, 4]),
            M.arrayClose.i
          ];
          expect(bjdataDecode(uint8Array(count, columnMajorData)), expected);
        });

        test('accepts optimized and non-optimized dimension arrays alike', () {
          expect(bjdataDecode(uint8Array(plainDims([2, 3, 4]), rowMajorData)), expected);
          expect(
            bjdataDecode(uint8Array(plainDims([2, 3, 4]), rowMajorData)),
            bjdataDecode(uint8Array(optimizedDims([2, 3, 4]), rowMajorData)),
          );
        });

        test('accepts a non-optimized wrapper around the dimension array', () {
          final count = [
            M.arrayOpen.i,
            ...plainDims([2, 3, 4]),
            M.arrayClose.i
          ];
          expect(bjdataDecode(uint8Array(count, columnMajorData)), expected);
        });

        test('keeps the innermost axis as a typed list', () {
          final decoded = bjdataDecode(uint8Array(optimizedDims([2, 3, 4]), rowMajorData));
          expect(decoded, isA<List>());
          expect(decoded[0], isA<List>());
          expect(decoded[0][0], isA<Uint8List>());
          expect(decoded[0][0], [1, 9, 6, 0]);
        });

        test('slices the payload rather than copying it', () {
          final decoded = bjdataDecode(uint8Array(optimizedDims([2, 3, 4]), rowMajorData));
          final first = decoded[0][0] as Uint8List;
          final last = decoded[1][2] as Uint8List;
          // One buffer holding all 24 elements, viewed at different offsets.
          expect(first.offsetInBytes, 0);
          expect(last.offsetInBytes, 20);
          expect(first.buffer.lengthInBytes, 24);
        });

        test('a single dimension behaves like a plain count', () {
          final decoded = bjdataDecode(uint8Array(optimizedDims([4]), [1, 2, 3, 4]));
          expect(decoded, isA<Uint8List>());
          expect(decoded, [1, 2, 3, 4]);
        });

        test('handles every strong type', () {
          final types = <BjdataMarker, int>{
            M.byte: 1,
            M.int8: 1,
            M.uint16: 2,
            M.int16: 2,
            M.uint32: 4,
            M.int32: 4,
            M.float32: 4,
            M.float64: 8,
            M.float16: 2,
            if (1 is! double) M.uint64: 8,
            if (1 is! double) M.int64: 8,
          };
          types.forEach((marker, size) {
            final encoded = [
              M.arrayOpen.i, M.strongType.i, marker.i, M.count.i, //
              ...optimizedDims([2, 2]),
              ...List.filled(4 * size, 0),
            ];
            final decoded = bjdataDecode(encoded);
            // Two rows, each still a typed view onto the one payload.
            expect((decoded as List).length, 2, reason: '$marker');
            expect(decoded[0], isA<TypedData>(), reason: '$marker');
          });
        });

        test('reorders column-major payloads of wider types', () {
          // A 2x2 int16 array, stored column-major as 1 3 2 4.
          final data = <int>[];
          for (final value in [1, 3, 2, 4]) {
            data.addAll([value, 0]);
          }
          final encoded = [
            M.arrayOpen.i, M.strongType.i, M.int16.i, M.count.i, //
            M.arrayOpen.i, ...optimizedDims([2, 2]), M.arrayClose.i,
            ...data,
          ];
          expect(bjdataDecode(encoded), [
            [1, 2],
            [3, 4],
          ]);
        });

        test('reshapes containers that are not strongly typed', () {
          // char is excluded from the packed path, so it exercises the element loop.
          final chars = [
            M.arrayOpen.i, M.strongType.i, M.char.i, M.count.i, //
            ...plainDims([2, 2]),
            0x61, 0x62, 0x63, 0x64,
          ];
          expect(bjdataDecode(chars), [
            ['a', 'b'],
            ['c', 'd'],
          ]);

          final mixed = [
            M.arrayOpen.i, M.count.i, ...plainDims([2, 2]), //
            M.uint8.i, 1, M.true_.i, M.null_.i, M.string.i, M.uint8.i, 1, 0x78,
          ];
          expect(bjdataDecode(mixed), [
            [1, true],
            [null, 'x'],
          ]);
        });

        group('encoding', () {
          /// Whether [encoded] is a container counted by a dimension array.
          bool isNd(List<int> encoded) =>
              encoded.length > 4 &&
              encoded[0] == M.arrayOpen.i &&
              encoded[1] == M.strongType.i &&
              encoded[3] == M.count.i &&
              encoded[4] == M.arrayOpen.i;

          test('writes a rectangular nesting of typed rows as one array', () {
            final rows = [
              Uint8List.fromList([1, 2, 3]),
              Uint8List.fromList([4, 5, 6]),
            ];
            expect(bjdataEncode(rows).hex, '5b2455235b550255035d010203040506');
            expect(bjdataDecode(bjdataEncode(rows)), rows);
          });

          test('round-trips what the decoder produces', () {
            final encoded = [
              M.arrayOpen.i, M.strongType.i, M.uint8.i, M.count.i, //
              M.arrayOpen.i, M.uint8.i, 2, M.uint8.i, 3, M.arrayClose.i,
              1, 2, 3, 4, 5, 6,
            ];
            expect(bjdataEncode(bjdataDecode(encoded)).hex, encoded.hex);
          });

          test('round-trips three dimensions', () {
            final encoded = [
              M.arrayOpen.i, M.strongType.i, M.float64.i, M.count.i, //
              M.arrayOpen.i, M.uint8.i, 2, M.uint8.i, 2, M.uint8.i, 2, M.arrayClose.i,
              ...List.filled(64, 0),
            ];
            expect(bjdataEncode(bjdataDecode(encoded)).hex, encoded.hex);
          });

          test('is smaller than nesting the rows', () {
            final rows = [Float64List(4), Float64List(4), Float64List(4)];
            expect(
              bjdataEncode(rows).length,
              lessThan(bjdataEncode(rows, config: const BjdataConfig(multiDimensional: false)).length),
            );
          });

          test('handles every typed list', () {
            final rows = <String, List<TypedData>>{
              'ByteData': [ByteData(2), ByteData(2)],
              'Uint8List': [Uint8List(2), Uint8List(2)],
              'Int8List': [Int8List(2), Int8List(2)],
              'Uint16List': [Uint16List(2), Uint16List(2)],
              'Int16List': [Int16List(2), Int16List(2)],
              'Uint32List': [Uint32List(2), Uint32List(2)],
              'Int32List': [Int32List(2), Int32List(2)],
              'Float32List': [Float32List(2), Float32List(2)],
              'Float64List': [Float64List(2), Float64List(2)],
              if (1 is! double) 'Uint64List': [Uint64List(2), Uint64List(2)],
              if (1 is! double) 'Int64List': [Int64List(2), Int64List(2)],
            };
            rows.forEach((reason, value) {
              final encoded = bjdataEncode(value);
              expect(isNd(encoded), isTrue, reason: reason);
              // ByteData has no value equality, so compare the bytes throughout.
              final decoded = bjdataDecode(encoded) as List;
              expect(decoded.length, value.length, reason: reason);
              for (var i = 0; i < value.length; i++) {
                expect(
                  Uint8List.sublistView(decoded[i] as TypedData),
                  Uint8List.sublistView(value[i]),
                  reason: '$reason row $i',
                );
              }
            });
          });

          test('leaves anything that is not a rectangular typed nesting alone', () {
            final untouched = <String, List<Object?>>{
              'rows of differing lengths': [Float64List(3), Float64List(2)],
              'rows of differing types': [Float64List(3), Float32List(3)],
              'a single row': [Float64List(3)],
              'empty rows': [Float64List(0), Float64List(0)],
              'an empty list': <Object?>[],
              // Matching how a flat list is written: only typed data is packed.
              'plain lists of numbers': [
                [1, 2],
                [3, 4],
              ],
              'rows mixed with other values': [Float64List(2), 'x'],
              'ragged nesting': [
                [Uint8List(2)],
                [Uint8List(2), Uint8List(2)],
              ],
            };
            untouched.forEach((reason, value) {
              final encoded = bjdataEncode(value);
              expect(isNd(encoded), isFalse, reason: reason);
              expect(bjdataDecode(encoded), value, reason: reason);
            });
          });

          test('gives up on self-referential lists instead of recursing', () {
            final list = <Object?>[];
            list.add(list);
            expect(() => bjdataEncode(list), throwsA(isA<BjdataCyclicError>()));
          });

          test('is governed by multiDimensional, not by the version', () {
            final rows = [Float64List(2), Float64List(2)];
            // N-dimensional arrays are a draft 3 construct, so capping the version
            // at draft 3 leaves them alone.
            expect(isNd(bjdataEncode(rows, config: BjdataConfig.draft3)), isTrue);
            expect(isNd(bjdataEncode(rows, config: const BjdataConfig(soa: BjdataSoaLayout.off))), isTrue);
            expect(isNd(bjdataEncode(rows, config: const BjdataConfig(multiDimensional: false))), isFalse);
            expect(bjdataDecode(bjdataEncode(rows, config: const BjdataConfig(multiDimensional: false))), rows);
          });

          test('renders in block notation', () {
            expect(
              bjdataBlockNotation([
                Uint8List.fromList([1, 2]),
                Uint8List.fromList([3, 4]),
              ]),
              '[[][\$][U][#][[][U][2][U][2][]][1][2][3][4]',
            );
          });
        });

        test('rejects malformed dimensions', () {
          final entries = <String, List<int>>{
            'an empty dimension array': [
              M.arrayOpen.i,
              M.strongType.i,
              M.uint8.i,
              M.count.i,
              M.arrayOpen.i,
              M.arrayClose.i,
            ],
            'a negative dimension': [
              M.arrayOpen.i,
              M.strongType.i,
              M.uint8.i,
              M.count.i,
              M.arrayOpen.i,
              M.int8.i,
              0xFF,
              M.arrayClose.i,
            ],
            'a non-integer dimension type': [
              M.arrayOpen.i, M.strongType.i, M.uint8.i, M.count.i, //
              M.arrayOpen.i, M.strongType.i, M.float64.i, M.count.i, M.uint8.i, 1, ...List.filled(8, 0),
            ],
            'an unclosed column-major wrapper': [
              M.arrayOpen.i, M.strongType.i, M.uint8.i, M.count.i, //
              M.arrayOpen.i, ...plainDims([2]), M.uint8.i, 1, 2,
            ],
            'an object counted by dimensions': [
              M.objectOpen.i, M.strongType.i, M.uint8.i, M.count.i, ...plainDims([1]), //
              M.uint8.i, 1, 0x61, 1,
            ],
            'a payload shorter than the dimensions': [
              M.arrayOpen.i,
              M.strongType.i,
              M.uint8.i,
              M.count.i,
              ...plainDims([2, 3]),
              1,
              2,
            ],
          };
          entries.forEach((reason, entry) {
            expect(() => bjdataDecode(entry), throwsA(isA<FormatException>()), reason: reason);
          });
        });

        test('re-encodes as nested arrays', () {
          // Encoding N-dimensional containers is not supported, so a decoded array
          // is written back as an array of arrays. The values are unchanged.
          final decoded = bjdataDecode(uint8Array(optimizedDims([2, 3, 4]), rowMajorData));
          expect(bjdataDecode(bjdataEncode(decoded)), expected);
        });
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

  group('soa', () {
    /// A schema field name, encoded the way the specification examples write it.
    List<int> name(String value) => [M.int8.i, value.length, ...utf8.encode(value)];
    List<int> f64(double value) => Uint8List.sublistView(ByteData(8)..setFloat64(0, value, Endian.little));
    List<int> u32(int value) => Uint8List.sublistView(ByteData(4)..setUint32(0, value, Endian.little));
    List<int> i32(int value) => Uint8List.sublistView(ByteData(4)..setInt32(0, value, Endian.little));

    /// Encodes an explicit schema, which auto-detection never produces on its
    /// own, by driving the writer directly.
    List<int> encodeSoa(BjdataSoaSchema schema, List<int> dimensions, List<Map<String, Object?>> records) {
      final builder = BytesBuilder();
      final writer = BjdataBufferWriter(null, 256, builder.add);
      writer.writeSoa(BjdataSoaCandidate(schema, dimensions, records), BjdataSoaLayout.rowMajor);
      writer.flush(refill: false);
      return builder.takeBytes();
    }

    group('detection', () {
      final table = [
        {'a': 1, 'b': 'x'},
        {'a': 2, 'b': 'y'},
      ];

      test('packs a uniform table by default', () {
        final encoded = bjdataEncode(table);
        expect(encoded.sublist(0, 3), [M.arrayOpen.i, M.strongType.i, M.objectOpen.i]);
        expect(
            encoded.length, lessThan(bjdataEncode(table, config: const BjdataConfig(soa: BjdataSoaLayout.off)).length));
        expect(bjdataDecode(encoded), table);
      });

      test('config: const BjdataConfig(soa: BjdataSoaLayout.off) writes a plain array of objects', () {
        final encoded = bjdataEncode(table, config: const BjdataConfig(soa: BjdataSoaLayout.off));
        expect(encoded.sublist(0, 2), [M.arrayOpen.i, M.objectOpen.i]);
        expect(bjdataDecode(encoded), table);
      });

      test('decoding never depends on the flag', () {
        expect(bjdataDecode(bjdataEncode(table)),
            bjdataDecode(bjdataEncode(table, config: const BjdataConfig(soa: BjdataSoaLayout.off))));
      });

      test('gives up on self-referential values instead of recursing', () {
        final list = <Object?>[];
        list.add(list);
        expect(() => bjdataEncode(list), throwsA(isA<BjdataCyclicError>()));

        final record = <String, Object?>{};
        record['self'] = record;
        expect(() => bjdataEncode([record, record]), throwsA(isA<BjdataCyclicError>()));

        final nested = <String, Object?>{};
        nested['a'] = [nested];
        expect(() => bjdataEncode([nested, nested]), throwsA(isA<BjdataCyclicError>()));
      });

      test('falls back to a plain array when a table is not uniform', () {
        final fallbacks = <String, List<Object?>>{
          'null in some records': [
            {'a': 1},
            {'a': null},
          ],
          'int mixed with double': [
            {'a': 1},
            {'a': 2.5},
          ],
          'differing field names': [
            {'a': 1},
            {'b': 2},
          ],
          'differing field counts': [
            {'a': 1, 'b': 2},
            {'a': 3},
          ],
          'nested objects with differing keys': [
            {
              'a': {'x': 1},
            },
            {
              'a': {'y': 1},
            },
          ],
          'arrays of differing lengths': [
            {
              'a': [1],
            },
            {
              'a': [1, 2],
            },
          ],
          'empty arrays': [
            {'a': <int>[]},
            {'a': <int>[]},
          ],
          'typed data fields': [
            {
              'a': Uint8List.fromList([1, 2]),
            },
            {
              'a': Uint8List.fromList([3, 4]),
            },
          ],
          'a single record': [
            {'a': 1},
          ],
          'no fields': [<String, Object?>{}, <String, Object?>{}],
          'values that are not records': [1, 2, 3],
          'ragged nesting': [
            [
              {'a': 1},
            ],
            [
              {'a': 2},
              {'a': 3},
            ],
          ],
          'an empty list': <Object?>[],
        };

        fallbacks.forEach((reason, value) {
          final encoded = bjdataEncode(value);
          expect(encoded[1], isNot(M.strongType.i), reason: reason);
          expect(bjdataDecode(encoded), value, reason: reason);
        });
      });

      test('does not make non-string keys encodable', () {
        final value = [
          {1: 'a'},
          {1: 'b'},
        ];
        expect(() => bjdataEncode(value), throwsA(isA<BjdataUnsupportedObjectError>()));
        expect(() => bjdataEncode(value), throwsA(isA<BjdataUnsupportedObjectError>()));
      });

      test('packs a table nested inside an object', () {
        final envelope = {
          'users': [
            {'id': 1},
            {'id': 2},
          ],
          'total': 2,
        };
        final encoded = bjdataEncode(envelope);
        expect(encoded.first, M.objectOpen.i);
        expect(bjdataDecode(encoded), envelope);
      });
    });

    group('layout', () {
      final records = <Map<String, Object?>>[
        {'id': 1, 'name': 'Alice', 'ok': true},
        {'id': 2, 'name': 'Bob', 'ok': false},
        {'id': 3, 'name': 'Charlie', 'ok': true},
      ];

      test('row-major is the default', () {
        expect(bjdataEncode(records).hex, bjdataEncode(records, config: const BjdataConfig()).hex);
      });

      test('row-major opens with an array marker', () {
        final encoded = bjdataEncode(records, config: const BjdataConfig());
        expect(encoded.sublist(0, 3), [M.arrayOpen.i, M.strongType.i, M.objectOpen.i]);
        expect(bjdataDecode(encoded), records);
      });

      test('column-major opens with an object marker', () {
        final encoded = bjdataEncode(records, config: const BjdataConfig(soa: BjdataSoaLayout.columnMajor));
        expect(encoded.sublist(0, 3), [M.objectOpen.i, M.strongType.i, M.objectOpen.i]);
      });

      test('column-major decodes to a map of columns', () {
        expect(bjdataDecode(bjdataEncode(records, config: const BjdataConfig(soa: BjdataSoaLayout.columnMajor))), {
          'id': [1, 2, 3],
          'name': ['Alice', 'Bob', 'Charlie'],
          'ok': [true, false, true],
        });
      });

      test('both layouts share a schema and a payload size', () {
        final rows = bjdataEncode(records, config: const BjdataConfig());
        final columns = bjdataEncode(records, config: const BjdataConfig(soa: BjdataSoaLayout.columnMajor));
        expect(columns.length, rows.length);
        // Identical but for the container marker and the order of the payload.
        expect(columns.sublist(1, 20), rows.sublist(1, 20));
        expect(columns.hex, isNot(rows.hex));
      });

      test('column-major groups each field together', () {
        final table = <Map<String, Object?>>[
          {'a': 1, 'b': 2},
          {'a': 3, 'b': 4},
        ];
        List<int> payloadOf(BjdataSoaLayout layout) {
          final encoded = bjdataEncode(table, config: BjdataConfig(soa: layout));
          return encoded.sublist(encoded.length - 4);
        }

        expect(payloadOf(BjdataSoaLayout.rowMajor), [1, 2, 3, 4]); // a b, a b
        expect(payloadOf(BjdataSoaLayout.columnMajor), [1, 3, 2, 4]); // a a, b b
      });

      test('offset tables follow the payload in both layouts', () {
        final table = <Map<String, Object?>>[
          {'s': 'a', 't': 'xx'},
          {'s': 'bb', 't': 'y'},
          {'s': 'ccc', 't': 'zzz'},
        ];
        for (final layout in [BjdataSoaLayout.rowMajor, BjdataSoaLayout.columnMajor]) {
          final encoded = bjdataEncode(table, config: BjdataConfig(soa: layout));
          final decoded = bjdataDecode(encoded);
          final expected = layout == BjdataSoaLayout.rowMajor
              ? table
              : {
                  's': ['a', 'bb', 'ccc'],
                  't': ['xx', 'y', 'zzz'],
                };
          expect(decoded, expected, reason: '$layout');
        }
      });

      test('n-dimensional works in both layouts', () {
        final grid = [
          for (var r = 0; r < 2; r++)
            [
              for (var c = 0; c < 3; c++) <String, Object?>{'x': r * 3 + c}
            ],
        ];
        expect(bjdataDecode(bjdataEncode(grid, config: const BjdataConfig())), grid);
        expect(bjdataDecode(bjdataEncode(grid, config: const BjdataConfig(soa: BjdataSoaLayout.columnMajor))), {
          'x': [
            [0, 1, 2],
            [3, 4, 5],
          ],
        });
      });

      test('off writes plain arrays of objects', () {
        final encoded = bjdataEncode(records, config: const BjdataConfig(soa: BjdataSoaLayout.off));
        expect(encoded.sublist(0, 2), [M.arrayOpen.i, M.objectOpen.i]);
        expect(bjdataDecode(encoded), records);
      });

      test('block notation renders both layouts', () {
        final table = [
          {'a': 1},
          {'a': 2},
        ];
        expect(bjdataBlockNotation(table, config: const BjdataConfig()), '[[][\$][{][U][1][a][U][}][#][U][2][1][2]');
        expect(
          bjdataBlockNotation(table, config: const BjdataConfig(soa: BjdataSoaLayout.columnMajor)),
          '[{][\$][{][U][1][a][U][}][#][U][2][1][2]',
        );
      });
    });

    group('round trip', () {
      void roundTrip(String reason, List<Object?> value) {
        test(reason, () {
          final encoded = bjdataEncode(value);
          expect(encoded.sublist(0, 3), [M.arrayOpen.i, M.strongType.i, M.objectOpen.i], reason: reason);
          expect(bjdataDecode(encoded), value, reason: reason);
        });
      }

      roundTrip('integer columns', [
        {'u8': 255, 'i8': -1, 'u16': 65535, 'i16': -300, 'u32': 4294967295, 'i32': -70000},
        {'u8': 0, 'i8': -128, 'u16': 0, 'i16': 300, 'u32': 0, 'i32': 70000},
      ]);
      roundTrip('double columns', [
        {'d': 1.5},
        {'d': -2.25},
        {'d': 1e300},
      ]);
      roundTrip('boolean and null columns', [
        {'b': true, 'z': null},
        {'b': false, 'z': null},
      ]);
      roundTrip('dictionary strings', [
        {'s': 'a'},
        {'s': 'b'},
        {'s': 'a'},
        {'s': 'b'},
      ]);
      roundTrip('offset table strings', [
        {'s': 'a'},
        {'s': 'bb'},
        {'s': 'ccc'},
      ]);
      roundTrip('empty strings', [
        {'s': ''},
        {'s': 'a'},
        {'s': ''},
      ]);
      roundTrip('non-ascii strings', [
        {'s': 'héllo'},
        {'s': 'wörld ✓'},
        {'s': '✓'},
      ]);
      roundTrip('high-precision columns', [
        {'h': BigInt.parse('123456789012345678901234567890')},
        {'h': BigInt.from(-42)},
        {'h': BigInt.parse('123456789012345678901234567890')},
      ]);
      roundTrip('nested objects', [
        {
          'p': {'x': 1.5, 'y': 2.5},
        },
        {
          'p': {'x': 3.5, 'y': 4.5},
        },
      ]);
      roundTrip('fixed arrays', [
        {
          'v': [1, 2, 3],
        },
        {
          'v': [4, 5, 6],
        },
      ]);
      roundTrip('deeply nested fields', [
        {
          'a': {
            'b': [
              {'c': 'x'},
              {'c': 'y'},
            ],
          },
        },
        {
          'a': {
            'b': [
              {'c': 'z'},
              {'c': 'x'},
            ],
          },
        },
      ]);
    });

    group('n-dimensional', () {
      final grid = [
        for (var r = 0; r < 4; r++)
          [
            for (var c = 0; c < 3; c++) <String, Object?>{'x': r * 3 + c}
          ],
      ];

      test('nested lists become a dimension array', () {
        expect(bjdataEncode(grid).hex, '5b247b550178557d235b550455035d000102030405060708090a0b');
      });

      test('decodes back to the same nesting', () {
        expect(bjdataDecode(bjdataEncode(grid)), grid);
      });

      test('handles three dimensions', () {
        final cube = [
          for (var i = 0; i < 2; i++)
            [
              for (var j = 0; j < 2; j++)
                [
                  for (var k = 0; k < 2; k++) <String, Object?>{'v': i * 4 + j * 2 + k}
                ],
            ],
        ];
        expect(bjdataDecode(bjdataEncode(cube)), cube);
      });

      test('accepts an optimized dimension array', () {
        final encoded = [
          M.arrayOpen.i, M.strongType.i, M.objectOpen.i, //
          M.uint8.i, 1, 0x78, M.uint8.i,
          M.objectClose.i,
          M.count.i, M.arrayOpen.i, M.strongType.i, M.uint8.i, M.count.i, M.uint8.i, 2, 4, 3,
          for (var i = 0; i < 12; i++) i,
        ];
        expect(bjdataDecode(encoded), grid);
      });
    });

    group('specification examples', () {
      test('decodes example 1, fixed-length fields only', () {
        final encoded = [
          M.arrayOpen.i, M.strongType.i, M.objectOpen.i, //
          ...name('id'), M.uint32.i,
          ...name('pos'), M.objectOpen.i, ...name('x'), M.float64.i, ...name('y'), M.float64.i, M.objectClose.i,
          ...name('val'), M.arrayOpen.i, M.float64.i, M.float64.i, M.float64.i, M.arrayClose.i,
          ...name('on'), M.true_.i,
          M.objectClose.i,
          M.count.i, M.int8.i, 2,
          ...u32(1), ...f64(1.0), ...f64(2.0), ...f64(0.1), ...f64(0.2), ...f64(0.3), M.true_.i,
          ...u32(2), ...f64(3.0), ...f64(4.0), ...f64(0.4), ...f64(0.5), ...f64(0.6), M.false_.i,
        ];
        // A 42 byte header and two 45 byte records, per the specification example.
        expect(encoded.length, 132);
        expect(bjdataDecode(encoded), [
          {
            'id': 1,
            'pos': {'x': 1.0, 'y': 2.0},
            'val': [0.1, 0.2, 0.3],
            'on': true,
          },
          {
            'id': 2,
            'pos': {'x': 3.0, 'y': 4.0},
            'val': [0.4, 0.5, 0.6],
            'on': false,
          },
        ]);
      });

      test('decodes example 2, variable-length string fields', () {
        final encoded = [
          M.arrayOpen.i, M.strongType.i, M.objectOpen.i, //
          ...name('id'), M.uint32.i,
          ...name('status'), M.arrayOpen.i, M.strongType.i, M.string.i, M.count.i, M.int8.i, 3,
          ...name('active'), ...name('inactive'), ...name('pending'),
          ...name('name'), M.arrayOpen.i, M.strongType.i, M.int32.i, M.arrayClose.i,
          ...name('code'), M.string.i, M.int8.i, 4,
          M.objectClose.i,
          M.count.i, M.int8.i, 3,
          // 13 byte records: id, status index, name index, fixed code.
          ...u32(1), 0, ...i32(0), ...utf8.encode('U001'),
          ...u32(2), 2, ...i32(1), ...utf8.encode('U002'),
          ...u32(3), 0, ...i32(2), ...utf8.encode('U003'),
          ...i32(0), ...i32(5), ...i32(8), ...i32(32),
          ...utf8.encode('AliceBobDr. Christopher Williams'),
        ];
        // 3 records of 13 bytes, a 4 entry int32 offset table and a 32 byte buffer.
        expect(encoded.length - (3 * 13 + 16 + 32), 72);
        expect(bjdataDecode(encoded), [
          {'id': 1, 'status': 'active', 'name': 'Alice', 'code': 'U001'},
          {'id': 2, 'status': 'pending', 'name': 'Bob', 'code': 'U002'},
          {'id': 3, 'status': 'active', 'name': 'Dr. Christopher Williams', 'code': 'U003'},
        ]);
      });
    });

    group('explicit schema', () {
      // Auto-detection never chooses these, so they are exercised through the
      // writer directly to keep the encoder and decoder in step.
      test('char, byte and null fields', () {
        final schema = BjdataSoaSchema({
          'c': BjdataSoaValueType(M.char),
          'b': BjdataSoaValueType(M.byte),
          'z': const BjdataSoaNullType(),
        });
        final records = <Map<String, Object?>>[
          {'c': 'a', 'b': 255, 'z': null},
          {'c': ';', 'b': 0, 'z': null},
        ];
        final encoded = encodeSoa(schema, [2], records);
        expect(schema.recordByteLength, 2);
        expect(encoded.sublist(encoded.length - 4).hex, '61ff3b00');
        expect(bjdataDecode(encoded), records);
      });

      test('float16 round-trips representable values', () {
        final values = [
          0.0,
          -0.0,
          1.0,
          -1.0,
          0.5,
          65504.0, // largest finite float16
          6.103515625e-5, // smallest normal float16
          5.960464477539063e-8, // smallest subnormal float16
          double.infinity,
          double.negativeInfinity,
        ];
        final schema = BjdataSoaSchema({'v': BjdataSoaValueType(M.float16)});
        final records = [
          for (final v in values) <String, Object?>{'v': v},
        ];
        final decoded = bjdataDecode(encodeSoa(schema, [values.length], records));
        for (var i = 0; i < values.length; i++) {
          expect(decoded[i]['v'], values[i], reason: 'float16 $i');
          expect((decoded[i]['v'] as double).isNegative, values[i].isNegative, reason: 'float16 sign $i');
        }
      });

      test('float16 rounds to nearest even', () {
        final schema = BjdataSoaSchema({'v': BjdataSoaValueType(M.float16)});
        final decoded = bjdataDecode(
          encodeSoa(schema, [
            4
          ], [
            {'v': 1 / 3},
            {'v': 1e-9},
            {'v': 1e9},
            {'v': double.nan},
          ]),
        );
        expect(decoded[0]['v'], 0.333251953125);
        expect(decoded[1]['v'], 0.0);
        expect(decoded[2]['v'], double.infinity);
        expect((decoded[3]['v'] as double).isNaN, isTrue);
      });

      test('float32 payloads', () {
        final schema = BjdataSoaSchema({'v': BjdataSoaValueType(M.float32)});
        final encoded = encodeSoa(schema, [
          2
        ], [
          {'v': 1.0},
          {'v': -2.5},
        ]);
        expect(encoded.sublist(encoded.length - 8).hex, '0000803f000020c0');
        expect(bjdataDecode(encoded), [
          {'v': 1.0},
          {'v': -2.5},
        ]);
      });

      test('pads and strips fixed-length strings', () {
        final schema = BjdataSoaSchema({'s': BjdataSoaFixedStringType(4)});
        final encoded = encodeSoa(schema, [
          2
        ], [
          {'s': 'ab'},
          {'s': ''},
        ]);
        expect(encoded.sublist(encoded.length - 8).hex, '6162000000000000');
        expect(bjdataDecode(encoded), [
          {'s': 'ab'},
          {'s': ''},
        ]);
      });

      test('fixed-length and dictionary high-precision fields', () {
        final huge = BigInt.parse('123456789012345678901234567890');
        final schema = BjdataSoaSchema({
          'd': BjdataSoaDictionaryType([BigInt.one, BigInt.two], huge: true),
          'f': BjdataSoaFixedStringType(31, huge: true),
        });
        final records = <Map<String, Object?>>[
          {'d': BigInt.one, 'f': huge},
          {'d': BigInt.two, 'f': -huge},
          {'d': BigInt.one, 'f': BigInt.zero},
        ];
        expect(bjdataDecode(encodeSoa(schema, [3], records)), records);
      });

      test('rejects values the schema cannot hold', () {
        final cases = <String, (BjdataSoaSchema, Object?)>{
          'a string in a numeric field': (
            BjdataSoaSchema({'a': BjdataSoaValueType(M.uint8)}),
            'x',
          ),
          'a missing field': (BjdataSoaSchema({'a': BjdataSoaValueType(M.uint8)}), null),
          'a string too long to fit': (BjdataSoaSchema({'a': BjdataSoaFixedStringType(2)}), 'toolong'),
          'a multi-character char': (BjdataSoaSchema({'a': BjdataSoaValueType(M.char)}), 'ab'),
          'a non-ascii char': (BjdataSoaSchema({'a': BjdataSoaValueType(M.char)}), 'é'),
          'a value not in the dictionary': (
            BjdataSoaSchema({
              'a': BjdataSoaDictionaryType(const ['x'])
            }),
            'y',
          ),
          'the wrong array length': (
            BjdataSoaSchema({
              'a': BjdataSoaArrayType([BjdataSoaValueType(M.uint8)]),
            }),
            [1, 2],
          ),
        };
        cases.forEach((reason, testCase) {
          final (schema, value) = testCase;
          expect(
            () => encodeSoa(schema, [
              1
            ], [
              if (value != null) {'a': value} else <String, Object?>{},
            ]),
            throwsA(isA<ArgumentError>()),
            reason: reason,
          );
        });
      });
    });

    group('schema', () {
      test('reports record byte lengths', () {
        expect(
          BjdataSoaSchema({
            'id': BjdataSoaValueType(M.uint32),
            'pos': BjdataSoaObjectType({
              'x': BjdataSoaValueType(M.float64),
              'y': BjdataSoaValueType(M.float64),
            }),
            'val': BjdataSoaArrayType([for (var i = 0; i < 3; i++) BjdataSoaValueType(M.float64)]),
            'on': const BjdataSoaBooleanType(),
          }).recordByteLength,
          45,
        );
      });

      test('keys offset fields by payload path', () {
        final schema = BjdataSoaSchema({
          'a': BjdataSoaOffsetType(M.uint8),
          'b': BjdataSoaObjectType({'c': BjdataSoaOffsetType(M.uint8)}),
          'd': BjdataSoaArrayType([BjdataSoaValueType(M.uint8), BjdataSoaOffsetType(M.uint8)]),
          'e': BjdataSoaValueType(M.uint8),
        });
        expect(schema.offsetFields.keys, ['a', 'b.c', 'd[1]']);
      });

      test('rejects invalid field types', () {
        expect(() => BjdataSoaValueType(M.string), throwsA(isA<ArgumentError>()));
        expect(() => BjdataSoaValueType(M.arrayOpen), throwsA(isA<ArgumentError>()));
        expect(() => BjdataSoaOffsetType(M.float64), throwsA(isA<ArgumentError>()));
        expect(() => BjdataSoaDictionaryType([]), throwsA(isA<ArgumentError>()));
        expect(() => BjdataSoaObjectType({}), throwsA(isA<ArgumentError>()));
        expect(() => BjdataSoaArrayType([]), throwsA(isA<ArgumentError>()));
      });

      test('sizes dictionary indices by dictionary size', () {
        expect(BjdataSoaDictionaryType(List.filled(255, 'a')).indexMarker, M.uint8);
        expect(BjdataSoaDictionaryType(List.filled(256, 'a')).indexMarker, M.uint16);
      });

      test('infers the narrowest integer marker', () {
        BjdataMarker markerFor(List<int> values) {
          final schema = BjdataSoaSchema.tryInfer([
            for (final v in values) {'a': v},
          ])!;
          return (schema.fields['a'] as BjdataSoaValueType).marker;
        }

        expect(markerFor([0, 255]), M.uint8);
        expect(markerFor([-1, 127]), M.int8);
        expect(markerFor([0, 65535]), M.uint16);
        expect(markerFor([-1, 300]), M.int16);
        expect(markerFor([0, 4294967295]), M.uint32);
        expect(markerFor([-1, 70000]), M.int32);
      });

      test('chooses dictionary or offset storage by repetition', () {
        BjdataSoaType typeFor(List<String> values) => BjdataSoaSchema.tryInfer([
              for (final v in values) {'a': v},
            ])!
                .fields['a']!;

        expect(typeFor(['a', 'b', 'a', 'b']), isA<BjdataSoaDictionaryType>());
        expect(typeFor(['a', 'bb', 'ccc']), isA<BjdataSoaOffsetType>());
      });

      test('never chooses lossy fixed-length strings', () {
        final schema = BjdataSoaSchema.tryInfer([
          {'a': 'x '},
          {'a': 'y'},
        ])!;
        expect(schema.fields['a'], isNot(isA<BjdataSoaFixedStringType>()));
      });
    });

    group('block notation', () {
      test('renders the schema and payload', () {
        expect(
          bjdataBlockNotation([
            {'id': 1, 'name': 'Alice', 'ok': true},
            {'id': 2, 'name': 'Bob', 'ok': false},
          ], indent: '  '),
          '[[][\$][{]\n'
          '  [U][2][id][U]\n'
          '  [U][4][name][[][\$][U][]]\n'
          '  [U][2][ok][T]\n'
          '[}][#][U][2]\n'
          '  [1][0][T]\n'
          '  [2][1][F]\n'
          '  [0][5][8]\n'
          '  [Alice][Bob]\n',
        );
      });

      test('config: const BjdataConfig(soa: BjdataSoaLayout.off) renders a plain array of objects', () {
        expect(
          bjdataBlockNotation([
            {'a': 1},
            {'a': 2},
          ], config: const BjdataConfig(soa: BjdataSoaLayout.off)),
          '[[][{][U][1][a][U][1][}][{][U][1][a][U][2][}][]]',
        );
      });
    });

    group('invalid', () {
      test('decoding rejects malformed containers', () {
        final entries = <String, List<int>>{
          'empty schema': [M.arrayOpen.i, M.strongType.i, M.objectOpen.i, M.objectClose.i, M.count.i, M.uint8.i, 0],
          'schema not followed by a count': [
            M.arrayOpen.i, M.strongType.i, M.objectOpen.i, M.uint8.i, 1, 0x61, M.uint8.i, M.objectClose.i, //
            M.uint8.i, 0,
          ],
          'invalid schema type marker': [
            M.arrayOpen.i, M.strongType.i, M.objectOpen.i, M.uint8.i, 1, 0x61, M.noop.i, M.objectClose.i, //
            M.count.i, M.uint8.i, 0,
          ],
          'truncated payload': [
            M.arrayOpen.i, M.strongType.i, M.objectOpen.i, M.uint8.i, 1, 0x61, M.uint8.i, M.objectClose.i, //
            M.count.i, M.uint8.i, 2, 1,
          ],
          'dictionary index out of range': [
            M.arrayOpen.i, M.strongType.i, M.objectOpen.i, M.uint8.i, 1, 0x61, //
            M.arrayOpen.i, M.strongType.i, M.string.i, M.count.i, M.uint8.i, 1, M.uint8.i, 1, 0x78, //
            M.objectClose.i, M.count.i, M.uint8.i, 1, 5,
          ],
          'invalid boolean payload byte': [
            M.arrayOpen.i, M.strongType.i, M.objectOpen.i, M.uint8.i, 1, 0x61, M.true_.i, M.objectClose.i, //
            M.count.i, M.uint8.i, 1, 0x00,
          ],
          'offset table type is not an integer': [
            M.arrayOpen.i, M.strongType.i, M.objectOpen.i, M.uint8.i, 1, 0x61, //
            M.arrayOpen.i, M.strongType.i, M.float64.i, M.arrayClose.i, M.objectClose.i, M.count.i, M.uint8.i, 0,
          ],
          'duplicate schema field': [
            M.arrayOpen.i, M.strongType.i, M.objectOpen.i, //
            M.uint8.i, 1, 0x61, M.uint8.i, M.uint8.i, 1, 0x61, M.uint8.i, M.objectClose.i, //
            M.count.i, M.uint8.i, 0,
          ],
          'negative dimension': [
            M.arrayOpen.i, M.strongType.i, M.objectOpen.i, M.uint8.i, 1, 0x61, M.uint8.i, M.objectClose.i, //
            M.count.i, M.arrayOpen.i, M.int8.i, 0xFF, M.arrayClose.i,
          ],
        };
        entries.forEach((reason, entry) {
          expect(() => bjdataDecode(entry), throwsA(isA<FormatException>()), reason: reason);
        });
      });
    });

    test('extension types are reported as unsupported', () {
      expect(
        () => bjdataDecode([0x45, 0x01, M.uint8.i, 0]),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('extension'))),
      );
    });
  });

  group('config', () {
    final records = <Map<String, Object?>>[
      {'a': 1},
      {'a': 2},
    ];
    final grid = [
      for (var r = 0; r < 2; r++)
        [
          for (var c = 0; c < 3; c++) <String, Object?>{'x': r * 3 + c}
        ],
    ];

    bool isSoa(List<int> encoded) => encoded[1] == M.strongType.i;

    group('version', () {
      test('draft 4 is the default', () {
        expect(const BjdataConfig().version, BjdataVersion.draft4);
        expect(isSoa(bjdataEncode(records)), isTrue);
      });

      test('draft 3 writes no packed tables', () {
        final encoded = bjdataEncode(records, config: BjdataConfig.draft3);
        expect(isSoa(encoded), isFalse);
        expect(bjdataDecode(encoded), records);
      });

      test('draft 3 overrides an explicitly requested layout', () {
        for (final layout in BjdataSoaLayout.values) {
          final config = BjdataConfig(version: BjdataVersion.draft3, soa: layout);
          expect(config.effectiveSoa, BjdataSoaLayout.off, reason: '$layout');
          expect(isSoa(bjdataEncode(records, config: config)), isFalse, reason: '$layout');
        }
      });

      test('draft 3 output is identical to turning packing off', () {
        expect(bjdataEncode(records, config: BjdataConfig.draft3).hex,
            bjdataEncode(records, config: const BjdataConfig(soa: BjdataSoaLayout.off)).hex);
      });

      test('draft 3 leaves everything else alone', () {
        // Structure-of-Arrays is the only draft 4 addition this library emits,
        // so nothing but a packed table should differ between the revisions.
        final value = {
          'i': 42,
          'd': 3.5,
          'b': true,
          'z': null,
          's': 'héllo',
          'h': BigInt.parse('123456789012345678901234567890'),
          'l': [1, 2, 3],
          'm': {'nested': 'x'},
          'binary': ByteData.sublistView(Uint8List.fromList([1, 2, 3])),
        };
        expect(bjdataEncode(value, config: BjdataConfig.draft3).hex, bjdataEncode(value).hex);
      });

      test('decoding ignores the version', () {
        final packed = bjdataEncode(records);
        expect(bjdataDecode(packed), records);
        expect(bjdataDecode(bjdataEncode(records, config: BjdataConfig.draft3)), records);
      });
    });

    group('multi-dimensional packing', () {
      test('is on by default', () {
        expect(const BjdataConfig().multiDimensional, isTrue);
        // A single container with a dimension array as its count.
        expect(bjdataEncode(grid).hex, startsWith('5b247b'));
        expect(bjdataDecode(bjdataEncode(grid)), grid);
      });

      test('off writes each inner table as its own container', () {
        final encoded = bjdataEncode(grid, config: const BjdataConfig(multiDimensional: false));
        // An ordinary array holding two packed tables, rather than one
        // container counted by a dimension array.
        expect(encoded.sublist(0, 4), [M.arrayOpen.i, M.arrayOpen.i, M.strongType.i, M.objectOpen.i]);
        expect(bjdataDecode(encoded), grid);
      });

      test('off still packs flat tables', () {
        final encoded = bjdataEncode(records, config: const BjdataConfig(multiDimensional: false));
        expect(isSoa(encoded), isTrue);
        expect(bjdataDecode(encoded), records);
      });

      test('off never writes a dimension array', () {
        final encoded = bjdataEncode(grid, config: const BjdataConfig(multiDimensional: false));
        // A dimension array is a count marker followed by an array marker.
        for (var i = 0; i < encoded.length - 1; i++) {
          expect(encoded[i] == M.count.i && encoded[i + 1] == M.arrayOpen.i, isFalse, reason: 'at $i');
        }
      });

      test('applies to the column-major layout too', () {
        const config = BjdataConfig(soa: BjdataSoaLayout.columnMajor, multiDimensional: false);
        final encoded = bjdataEncode(grid, config: config);
        expect(encoded.first, M.arrayOpen.i);
        expect(bjdataDecode(encoded), [
          {
            'x': [0, 1, 2],
          },
          {
            'x': [3, 4, 5],
          },
        ]);
      });
    });

    test('copyWith replaces only what it is given', () {
      const config = BjdataConfig(soa: BjdataSoaLayout.columnMajor, multiDimensional: false);
      expect(
          config.copyWith(version: BjdataVersion.draft3),
          const BjdataConfig(
            version: BjdataVersion.draft3,
            soa: BjdataSoaLayout.columnMajor,
            multiDimensional: false,
          ));
      expect(config.copyWith(), config);
    });

    test('presets say what they mean', () {
      expect(BjdataConfig.draft3.version, BjdataVersion.draft3);
      expect(BjdataConfig(soa: BjdataSoaLayout.off).soa, BjdataSoaLayout.off);
      expect(BjdataConfig(multiDimensional: false).multiDimensional, isFalse);
    });

    test('is carried by the codec and its converters', () {
      const codec = BjdataCodec(config: BjdataConfig(soa: BjdataSoaLayout.off));
      expect(isSoa(codec.encode(records)), isFalse);
      expect(isSoa(codec.encoder.convert(records)), isFalse);
      // A per-call config overrides the one the codec was built with.
      expect(isSoa(codec.encode(records, config: const BjdataConfig())), isTrue);
    });
  });

  group('utf-8 strings', () {
    test('length prefixes count bytes, not code units', () {
      // 'é' is two UTF-8 bytes but one UTF-16 code unit.
      expect(bjdataEncode('héllo').hex, '53550668c3a96c6c6f');
      expect(bjdataDecode(bjdataEncode('héllo')), 'héllo');
      expect(bjdataDecode(bjdataEncode({'kéy': 'vålue ✓'})), {'kéy': 'vålue ✓'});
    });
  });
}
