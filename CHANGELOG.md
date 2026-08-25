## 0.10.0
- Update to the BJData draft 4 specification
- Add Structure-of-Arrays (SoA) support
  - **Encoding now packs uniform tables of records by default.** A list of two or more
    records sharing the same field names and per-field types is written as an SoA
    container rather than an array of objects. No wrapper types are involved, and lists
    that are not uniform tables are unaffected, so the decoded values never change.
    Pass `soa: BjdataSoaLayout.off` (or `--no-soa`) to keep writing plain arrays of
    objects, which matters if the consumer only understands draft 3
  - `soa: BjdataSoaLayout.columnMajor` (or `--column-major`) packs each field
    contiguously instead of each record. Both layouts carry the same schema and the
    same number of payload bytes, so the choice is about how the consumer reads the
    data; a column-major container is an object of named arrays and so decodes to a
    map of columns rather than a list of records
  - Nested rectangular lists of records become N-dimensional containers
  - Decoding always understands both layouts: row-major (`[$`) becomes a `List` of
    record `Map`s, column-major (`{$`) a `Map` of column `List`s, and N-dimensional
    containers keep their nesting
  - Fixed-length, dictionary and offset-table string storage, nested objects, fixed
    arrays, boolean and null fields are all supported
- Reject extension types (`E`) with an explicit `FormatException`; they are not implemented
- Fix string length prefixes counting UTF-16 code units instead of UTF-8 bytes, which
  produced undecodable output for any non-ASCII string
- Add `--no-soa` and `--column-major` flags to the `bjdata` executable

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
