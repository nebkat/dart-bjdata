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
