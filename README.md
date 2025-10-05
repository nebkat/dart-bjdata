bjdata
======

[BJData](https://bjdata.org) (draft 3 specification) implementation in Dart.

![Dart version](https://img.shields.io/badge/Dart-3.1%2B-blue) [![License](https://img.shields.io/github/license/nebkat/dart-bjdata?cacheSeconds=3600&color=informational&label=License)](./LICENSE.md)

[![Pub package](https://img.shields.io/pub/v/bjdata.svg)](https://pub.dev/packages/bjdata) [![Build status](https://github.com/nebkat/dart-bjdata/actions/workflows/bjdata.yml/badge.svg)](https://github.com/nebkat/dart-bjdata/actions/workflows/bjdata.yml) [![Coverage status](https://coveralls.io/repos/github/nebkat/dart-bjdata/badge.svg)](https://coveralls.io/github/nebkat/dart-bjdata)

Encoding/decoding of BJData to/from Dart objects in an API based on the `dart:convert` package.

## Usage

```dart
import 'package:bjdata/bjdata.dart';

void main() {
    final List<int> encoded = bjdataEncode({
        'hello': 'world',
        'pi': 3.14159,
        'happy': true,
        'list': [1, 0, 1],
        'binary': ByteData.sublistView(Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF])),
        'nothing': null,
    });
    
    final decoded = bjdataDecode(encoded);

    print(bjdataBlockNotation(null)); // [Z]
    print(bjdataBlockNotation(true)); // [T]
    print(bjdataBlockNotation(false)); // [F]
    print(bjdataBlockNotation(42)); // [U][42]
    print(bjdataBlockNotation(3.14)); // [D][3.14]
    print(bjdataBlockNotation('Hello, world!')); // [S][U][13][Hello, world!]
    print(bjdataBlockNotation([1, 2, 3])); // [[][U][1][U][2][U][3][]]
    print(bjdataBlockNotation({'foo': 1, 'bar': 2})); // [{][U][3][foo][U][1][U][3][bar][U][2][}]
}
```

## Tool
```bash
dart pub global activate bjdata

# Show help
bjdata -h
# or
dart pub global run bjdata -h

# Encode a JSON file to BJData
bjdata encode input.json output.bjda

# Decode a BJData file to JSON
bjdata decode input.bjd output.json

# Pretty-print a JSON file in BJData block notation
bjdata print input.json

# stdin/stdout can be used instead of filenames
cat input.json | bjdata encode
cat input.bjd | bjdata decode
echo -n "[1, 2, 3]" | bjdata print
```

## Types

### Decoding BJData to Dart
- Multi dimensional arrays are not yet supported.

| BJData Type      | Marker | Dart                           |
|------------------|--------|--------------------------------|
| `null`           | `Z`    | `null`                         |
| `true`           | `T`    | `true`                         |
| `false`          | `F`    | `false`                        |
| `int8`           | `i`    | `int`                          |
| `uint8`          | `U`    | `int`                          |
| `int16`          | `u`    | `int`                          |
| `uint16`         | `I`    | `int`                          |
| `int32`          | `l`    | `int`                          |
| `uint32`         | `m`    | `int`                          |
| `int64`          | `L`    | `int`                          |
| `uint64`         | `M`    | `int` [*](#decode-int-warning) |
| `float16`        | `h`    | `double`                       |
| `float32`        | `d`    | `double`                       |
| `float64`        | `D`    | `double`                       |
| `byte`           | `B`    | `int`                          |
| `char`           | `C`    | `String`                       |
| `string`         | `S`    | `String`                       |
| `huge`           | `H`    | `BigInt`                       |
| `array`          | `[]`   | `List`                         |
| `array[byte]`    | `[$B`  | `ByteData`                     |
| `array[int8]`    | `[$i`  | `Int8List`                     |
| `array[uint8]`   | `[$U`  | `Uint8List`                    |
| `array[int16]`   | `[$u`  | `Int16List`                    |
| `array[uint16]`  | `[$I`  | `Uint16List`                   |
| `array[int32]`   | `[$l`  | `Int32List`                    |
| `array[uint32]`  | `[$m`  | `Uint32List`                   |
| `array[int64]`   | `[$L`  | `Int64List`                    |
| `array[uint64]`  | `[$M`  | `Uint64List`                   |
| `array[float16]` | `[$h`  | `Float32List`                  |
| `array[float32]` | `[$d`  | `Float32List`                  |
| `array[float64]` | `[$D`  | `Float64List`                  |
| `object`         | `{}`   | `Map`                          |

<a name="decode-int-warning">\*</a>
    Warning: `int` in Dart is a signed 64-bit integer. `uint64`/`M` values are decoded as `int64`
    (i.e. values greater than `9223372036854775807` are decoded as negative values).

### Encoding Dart to BJData
| Dart          | Marker    | BJData Type                                    |
|---------------|-----------|------------------------------------------------|
| `null`        | `Z`       | `null`                                         |
| `bool`        | `TF`      | `bool`                                         |
| `int`         | `UiIumlL` | `int` [*](#encode-int-notice)                  |
| `double`      | `D`       | `float64`                                      |
| `String`      | `S`       | `string`                                       |
| `BigInt`      | `H`       | `huge`                                         |
| `List`        | `[]`      | `array`                                        |
| `ByteData`    | `[$B`     | `array[byte]` [**](#encode-binary-data-notice) |
| `Int8List`    | `[$i`     | `array[int8]`                                  |
| `Uint8List`   | `[$U`     | `array[uint8]`                                 |
| `Int16List`   | `[$u`     | `array[int16]`                                 |
| `Uint16List`  | `[$I`     | `array[uint16]`                                |
| `Int32List`   | `[$l`     | `array[int32]`                                 |
| `Uint32List`  | `[$m`     | `array[uint32]`                                |
| `Int64List`   | `[$L`     | `array[int64]`                                 |
| `Uint64List`  | `[$M`     | `array[uint64]`                                |
| `Float32List` | `[$d`     | `array[float32]`                               |
| `Float64List` | `[$D`     | `array[float64]`                               |
| `Map`         | `{}`      | `object`                                       |

<a name="encode-int-notice">\*</a>
    `int` values are encoded using the smallest integer type possible, favouring unsigned types.

<a name="encode-binary-data-notice">\**</a> `ByteData` is recommended for encoding "binary data" as per the BJData specification
    (as this may affect how the data is parsed in other libraries). Converting from `Uint8List`
    to `ByteData` can be done using `ByteData.sublistView(list)`.

## Web
The package can be used in web applications, however it is affected by the [JavaScript number
peculiarities](https://dart.dev/resources/language/number-representation#differences-in-behavior).

- `int` values greater than `9007199254740991` (2^53 - 1) may lose precision when encoding/decoding.
- `double` values without a fractional part will be encoded as `int` (important if consumer strictly 
expects a double value).
- `Int64List` and `Uint64List` are not supported on web, so `array[int64]` and `array[uint64]`
  will be decoded as `List<int>`.