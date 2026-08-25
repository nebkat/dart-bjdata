## 0.10.0
- Update to the BJData draft 4 specification
- Add Structure-of-Arrays (SoA) support
  - **Encoding now packs uniform tables of records by default.** A list of two or more
    records sharing the same field names and per-field types is written as an SoA
    container rather than an array of objects. No wrapper types are involved, and lists
    that are not uniform tables are unaffected, so the decoded values never change.
    Pass `BjdataConfig(soa: BjdataSoaLayout.off)` (or `--no-soa`) to keep writing plain arrays of
    objects
  - `BjdataSoaLayout.columnMajor` (or `--column-major`) packs each field
    contiguously instead of each record. Both layouts carry the same schema and the
    same number of payload bytes, so the choice is about how the consumer reads the
    data; a column-major container is an object of named arrays and so decodes to a
    map of columns rather than a list of records
  - Nested rectangular lists of records become N-dimensional containers, unless
    `multiDimensional` is false (or `--no-nd`). Dimension-array counts are a draft 3
    construct, older than the packed tables that are currently the only thing this
    library writes them for
  - Decoding always understands both layouts: row-major (`[$`) becomes a `List` of
    record `Map`s, column-major (`{$`) a `Map` of column `List`s, and N-dimensional
    containers keep their nesting
  - Fixed-length, dictionary and offset-table string storage, nested objects, fixed
    arrays, boolean and null fields are all supported
- Add `BjdataConfig`, which carries the encoding settings for `bjdataEncode`,
  `bjdataBlockNotation`, `BjdataCodec`, `BjdataEncoder` and `BjdataBlockNotationEncoder`
  - `version` caps what may be written: `BjdataVersion.draft3` (or `--draft=3`) never
    writes Structure-of-Arrays containers, whatever layout is requested. SoA is the only
    draft 4 addition this library emits, so draft 3 and draft 4 output is otherwise
    byte-identical
- Write N-dimensional arrays as well as read them: a rectangular nesting of typed lists
  of the same type and length, such as a `List<Float64List>`, is written as one array
  counted by a dimension array rather than as an array of arrays. This makes a decoded
  N-dimensional array round-trip to the same bytes. As with a flat list, only typed data
  is packed, so a `List<List<double>>` is unaffected
- Reject extension types (`E`) with an explicit `FormatException`; they are not implemented
- Fix string length prefixes counting UTF-16 code units instead of UTF-8 bytes, which
  produced undecodable output for any non-ASCII string
- Add `--draft=N`, `--no-soa`, `--column-major` and `--no-nd` flags to the `bjdata`
  executable

## 0.9.3
- Support decoding N-dimensional arrays, which are a draft 3 construct that was previously
  rejected as invalid
  - `[$type#[Nx Ny ...]` decodes to nested lists, with the innermost axis kept as the typed
    list. The nested lists are views onto one buffer rather than copies, so the payload is
    still a single contiguous allocation
  - The column-major form, `[$type#[[Nx Ny ...]]` as written by MATLAB and FORTRAN, is
    reordered into row-major order so that it reads the same way
  - Dimension arrays are accepted in both optimized and non-optimized form
  - Encoding N-dimensional arrays is not supported, so a decoded array is written back as
    nested arrays; the values are unchanged
- Throw a `FormatException` instead of a `RangeError` when a string or buffer runs past the
  end of the input

## 0.9.2
- Update description to improve package score

## 0.9.1
- Fix bjdata executable `block` command

## 0.9.0
- Initial version.
