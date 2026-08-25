import 'soa.dart';
import 'version.dart';

/// How BJData is written.
///
/// Every encoding entry point takes one of these, so the settings can be
/// declared once and passed around rather than threaded through call sites
/// individually. The defaults target the current specification revision with
/// Structure-of-Arrays packing enabled.
///
/// Decoding accepts everything this library understands, so none of these
/// settings affect it.
final class BjdataConfig {
  /// Creates a configuration, defaulting to draft 4 with row-major
  /// Structure-of-Arrays packing.
  const BjdataConfig({
    this.version = BjdataVersion.draft4,
    this.soa = BjdataSoaLayout.rowMajor,
    this.multiDimensional = true,
  });

  /// The specification revision to stay within.
  ///
  /// Acts as a ceiling: [BjdataVersion.draft3] suppresses Structure-of-Arrays
  /// containers whatever [soa] asks for, since a draft 3 reader cannot parse
  /// them. See [effectiveSoa].
  final BjdataVersion version;

  /// The layout used for lists that are uniform tables of records.
  final BjdataSoaLayout soa;

  /// Whether a container may be counted by a dimension array (`#[Nx Ny ...]`)
  /// rather than by a single integer.
  ///
  /// Dimension arrays are a draft 3 construct, and two things are written with
  /// one: a rectangular nesting of typed rows such as a `List<Float64List>`
  /// becomes one N-dimensional array, and a rectangular nesting of records
  /// becomes one N-dimensional packed table.
  ///
  /// When false, neither is collapsed; the nesting is written as nested arrays,
  /// each of which may still be packed on its own, so the values are unchanged
  /// either way. Turn it off for consumers that read a container counted by an
  /// integer but not one counted by a dimension array.
  final bool multiDimensional;

  /// Output a BJData draft 3 reader can parse, with no Structure-of-Arrays
  /// containers.
  ///
  /// Named settings like this one describe a whole configuration, so the other
  /// fields take their defaults. To change one setting of an existing
  /// configuration, use [copyWith].
  static const BjdataConfig draft3 = BjdataConfig(version: BjdataVersion.draft3);

  /// The layout actually used, once [version] has had its say.
  ///
  /// [BjdataVersion.draft3] cannot express a Structure-of-Arrays container, so
  /// it overrides [soa] rather than being overridden by it.
  BjdataSoaLayout get effectiveSoa => version == BjdataVersion.draft3 ? BjdataSoaLayout.off : soa;

  /// A copy of this configuration with the given settings replaced.
  BjdataConfig copyWith({BjdataVersion? version, BjdataSoaLayout? soa, bool? multiDimensional}) => BjdataConfig(
        version: version ?? this.version,
        soa: soa ?? this.soa,
        multiDimensional: multiDimensional ?? this.multiDimensional,
      );

  @override
  bool operator ==(Object other) =>
      other is BjdataConfig &&
      other.version == version &&
      other.soa == soa &&
      other.multiDimensional == multiDimensional;

  @override
  int get hashCode => Object.hash(version, soa, multiDimensional);

  @override
  String toString() => 'BjdataConfig(version: $version, soa: $soa, multiDimensional: $multiDimensional)';
}
