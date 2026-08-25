bjdata
======

[BJData](https://github.com/neurojson/bjdata) (draft 4 specification) implementation in Dart.

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

## Structure-of-Arrays

Draft 4 adds [Structure-of-Arrays (SoA)](https://github.com/NeuroJSON/bjdata/blob/Draft-4/Binary_JData_Specification.md#structure-of-arrays)
containers, which store a table of uniform records as a payload-less schema followed by
tightly packed binary data, instead of repeating every field name in every record.

There are no special types to use, and nothing to switch on. Any list that turns out to be
a uniform table of records is packed automatically:

```dart
final records = [
    {'id': 1, 'name': 'Alice', 'active': true},
    {'id': 2, 'name': 'Bob', 'active': false},
];

bjdataEncode(records); // Structure-of-Arrays container
bjdataDecode(encoded); // List<Map<String, Object?>>
```

### Configuration

Encoding takes a `BjdataConfig`, so the settings are declared once rather than threaded
through call sites:

```dart
const config = BjdataConfig(
    version: BjdataVersion.draft4,  // specification revision to stay within
    soa: BjdataSoaLayout.rowMajor,  // how tables are packed
    multiDimensional: true,         // may a dimension array be used as a count
);

bjdataEncode(value, config: config);

// or set it once on a codec
const codec = BjdataCodec(config: BjdataConfig.draft3);
codec.encode(value);
```

Decoding accepts everything this library understands, so none of these affect it.

### Layout

`soa` selects how the payload is arranged, or turns the packing off:

| `BjdataSoaLayout` | Marker | Payload | Decodes to |
|---|---|---|---|
| `rowMajor` (default) | `[$` | Each record contiguous | `List` of record `Map`s |
| `columnMajor` | `{$` | Each field contiguous | `Map` of column `List`s |
| `off` | — | Plain array of objects | `List` of record `Map`s |

```dart
final table = [
    {'a': 1, 'b': 2},
    {'a': 3, 'b': 4},
];

bjdataEncode(table); // payload 1 2, 3 4
bjdataEncode(table, config: const BjdataConfig(soa: BjdataSoaLayout.columnMajor)); // 1 3, 2 4
bjdataEncode(table, config: BjdataConfig(soa: BjdataSoaLayout.off)); // array of objects
```

The two SoA layouts carry the same schema and exactly as many payload bytes, so the choice
is about access, not size: a column-major container stores each field as one contiguous
run, which suits a reader that walks fields rather than records. Nothing in the data says
which is better — that depends on the consumer, which is why it is a parameter rather than
something detected.

Note that a column-major container is an object of named arrays, so it decodes to a `Map`
of columns rather than to the list of records that produced it:

```dart
bjdataDecode(bjdataEncode(records, soa: BjdataSoaLayout.columnMajor));
// {'id': [1, 2], 'name': ['Alice', 'Bob'], 'active': [true, false]}
```

Use `BjdataSoaLayout.off` when the consumer only understands draft 3.

Decoding never needs the flag and never returns a special type: a row-major container
(`[$`) decodes to a `List` of record `Map`s and a column-major one (`{$`) to a `Map` of
column `List`s.

Nested lists become an N-dimensional container, and come back with the same nesting:

```dart
final grid = [
    [{'x': 0}, {'x': 1}, {'x': 2}],
    [{'x': 3}, {'x': 4}, {'x': 5}],
];

bjdataEncode(grid);    // [${x:U}#[U2 U3] followed by six packed records
bjdataDecode(encoded); // the same 2x3 nesting of records
```

Dimension-array counts (`#[Nx Ny ...]`) are a draft 3 construct, older than the packed
tables that are currently the only thing this library writes them for. Set
`multiDimensional: false` for a consumer that reads a container counted by an integer but
not one counted by a dimension array; each inner table is then packed on its own inside an
ordinary array, so the values are unchanged either way.

### Compatibility

`version` is a ceiling on what may be written. `BjdataVersion.draft3` never writes packed
tables, whatever layout is asked for, since a draft 3 reader cannot parse them:

```dart
bjdataEncode(records, config: BjdataConfig.draft3); // array of objects
```

Structure-of-Arrays is the only draft 4 addition this library emits — extension types (`E`)
are not implemented — so draft 3 and draft 4 output is byte-identical for everything else,
and `BjdataConfig.draft3` and `BjdataConfig(soa: BjdataSoaLayout.off)` currently produce the same bytes.
Prefer `draft3` when the reason is the consumer's age, so that later revisions stay capped
too.

### What gets packed

A list is packed only when every record agrees, so the decoded values are always identical
to what you passed in. Anything else is written as a plain array of objects:

| Packed                                            | Left as a plain array                          |
|---------------------------------------------------|------------------------------------------------|
| Two or more records with the same field names      | A single record, or an empty list              |
| Fields with one type across every record           | A field that is `null` in some records only    |
| `int` fields (narrowest marker that fits)          | A field mixing `int` and `double`              |
| `double`, `bool`, all-`null` fields                | Fields holding `TypedData`                     |
| `String` fields (dictionary or offset table)       | Records with non-`String` keys                 |
| `BigInt` fields (high-precision dictionary)        | Ragged nested lists                            |
| Nested objects and equal-length arrays             | Empty or differently sized nested arrays       |

A single record is never packed, because its schema costs about as much as the object it
would replace.

### Cost

Detection is a single pass over the list, and it is cheaper than what it saves. Encoding
100,000 records of five fields on a VM build:

| | Time | Size |
|---|---|---|
| `BjdataConfig(soa: BjdataSoaLayout.off)` | 70 ms | 5.5 MB |
| default (`rowMajor`) | 51 ms | 2.4 MB |
| default, table rejected on the last field | 92 ms | 5.5 MB |

Packing is *faster* than not packing, because roughly half as many bytes are written. The
worst case — a list that looks uniform until the very last field and then falls back —
costs about 30% over a plain encode. A list that is obviously not a table (its first
element is not a record) is rejected immediately and costs nothing measurable.

## Tool
```bash
dart pub global activate bjdata

# Show help
bjdata -h
# or
dart pub global run bjdata -h

# Encode a JSON file to BJData
bjdata encode input.json output.bjda

# Options: --draft=N, --no-soa, --column-major, --no-nd
bjdata encode input.json output.bjd --column-major
bjdata encode input.json output.bjd --draft=3

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
- N-dimensional arrays (`#[Nx Ny ...]`) decode to nested lists, with the innermost axis
  kept as the typed list. Both row-major and column-major (`#[[Nx Ny ...]]`) orderings are
  read; a column-major payload is reordered so that it reads the same way. Writing a
  dimension array is only supported for [SoA containers](#structure-of-arrays), so a
  decoded N-dimensional array is written back as nested arrays.
- Extension types (`E`) are not supported and are rejected with a `FormatException`.

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
| `array[T]` N-D   | `#[`   | Nested `List` of `T`           |
| `soa[rows]`      | `[${`  | `List<Map>` [†](#soa-note)     |
| `soa[columns]`   | `{${`  | `Map<String, List>` [†](#soa-note) |

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
| `List<Map>`   | `[${`     | `soa` (row-major) [†](#soa-note)               |
| `List<Map>`   | `{${`     | `soa` (column-major) [†](#soa-note)            |

<a name="soa-note">†</a> See [Structure-of-Arrays](#structure-of-arrays). The layout, the
    specification revision and N-dimensional packing are all chosen with `config:`.
    Column-major containers decode to a map of columns rather than a list of records.

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