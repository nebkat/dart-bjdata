import 'package:bjdata/bjdata.dart';

void main() {
  final value = <String, dynamic>{
    'a': 1,
    'b': '2',
    'c': [1, 2, 3],
    'd': {'e': 4, 'f': '5'},
  };

  final bytes = bjdata.encode(value);
  print(String.fromCharCodes(bytes));
  print(bytes);

  final v2 = bjdata.decode(bytes);

  print(v2);
}
