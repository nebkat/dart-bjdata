import 'dart:typed_data';

import 'package:bjdata/bjdata.dart';

void main() {
  final value = <String, dynamic>{
    'a': 1,
    'b': '2',
    'c': [1, 2, 3],
    'd': {'e': 3.14, 'f': true},
    'g': BigInt.parse('12345678901234567890'),
    'h': null,
    'i': Uint8List.fromList([1, 2, 3, 4, 5]),
  };

  final bytes = bjdataEncode(value);
  print(bytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join(''));
  print(bjdataDecode(bytes));

  print(bjdataBlockNotation(value, indent: '  '));

  print(bjdataBlockNotation(null)); // [Z]
  print(bjdataBlockNotation(true)); // [T]
  print(bjdataBlockNotation(false)); // [F]
  print(bjdataBlockNotation(42)); // [U][42]
  print(bjdataBlockNotation(3.14)); // [D][3.14]
  print(bjdataBlockNotation('Hello, world!')); // [S][U][13][Hello, world!]
  print(bjdataBlockNotation([1, 2, 3])); // [[][U][1][U][2][U][3][]]
  print(bjdataBlockNotation({'foo': 1, 'bar': 2})); // [{][U][3][foo][U][1][U][3][bar][U][2][}]

  // Structure-of-Arrays: uniform tables of records are packed behind a schema
  // automatically. No special types are involved either way.
  final records = [
    {'id': 1, 'name': 'Alice', 'active': true},
    {'id': 2, 'name': 'Bob', 'active': false},
  ];
  print(bjdataBlockNotation(records, indent: '  '));
  print(bjdataEncode(records, config: const BjdataConfig(soa: BjdataSoaLayout.off)).length); // 62
  print(bjdataEncode(records).length); // 48
  print(bjdataDecode(bjdataEncode(records))); // the same records

  // Nested lists become an N-dimensional container and keep their nesting.
  final grid = [
    [
      {'x': 0},
      {'x': 1},
      {'x': 2}
    ],
    [
      {'x': 3},
      {'x': 4},
      {'x': 5}
    ],
  ];
  print(bjdataBlockNotation(grid));
  print(bjdataDecode(bjdataEncode(grid))); // the same 2x3 nesting

  // Column-major packs each field contiguously instead. It holds the same bytes
  // in a different order, and decodes to a map of columns rather than records.
  print(bjdataBlockNotation(records, config: const BjdataConfig(soa: BjdataSoaLayout.columnMajor)));
  print(bjdataDecode(bjdataEncode(records, config: const BjdataConfig(soa: BjdataSoaLayout.columnMajor))));
}
