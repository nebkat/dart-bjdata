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
}
