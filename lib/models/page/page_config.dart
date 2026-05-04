/// Configuration for page mode — how a pattern is split into pages.
/// Persisted in the .stitches YAML file under the `pageMode:` key.
class PageConfig {
  final bool enabled;

  /// Number of columns (stitches) per page.
  final int pageWidth;

  /// Number of rows (stitches) per page.
  final int pageHeight;

  /// Cell count controlling boundary flexibility (0 = straight edge, default ~4).
  ///
  /// Plays double duty:
  ///   1. **Object rule**: a super-group that bleeds ≤ tolerance cells across a
  ///      boundary is kept whole on its majority page.
  ///   2. **Edge shift**: the smooth-edge DP may deviate at most ±tolerance cells
  ///      from the nominal boundary at any row.
  final int tolerance;

  const PageConfig({
    required this.enabled,
    required this.pageWidth,
    required this.pageHeight,
    required this.tolerance,
  });

  static const PageConfig disabled = PageConfig(
    enabled: false,
    pageWidth: 50,
    pageHeight: 50,
    tolerance: 5,
  );

  PageConfig copyWith({
    bool? enabled,
    int? pageWidth,
    int? pageHeight,
    int? tolerance,
  }) =>
      PageConfig(
        enabled: enabled ?? this.enabled,
        pageWidth: pageWidth ?? this.pageWidth,
        pageHeight: pageHeight ?? this.pageHeight,
        tolerance: tolerance ?? this.tolerance,
      );

  Map<String, dynamic> toYaml() => {
        'enabled': enabled,
        'pageWidth': pageWidth,
        'pageHeight': pageHeight,
        'tolerance': tolerance,
      };

  factory PageConfig.fromYaml(Map yaml) => PageConfig(
        enabled: yaml['enabled'] as bool? ?? false,
        pageWidth: yaml['pageWidth'] as int? ?? 50,
        pageHeight: yaml['pageHeight'] as int? ?? 50,
        // Accept both new 'tolerance' key and legacy 'fuzzyAmount' for migration.
        tolerance: yaml['tolerance'] as int? ?? yaml['fuzzyAmount'] as int? ?? 5,
      );

  @override
  bool operator ==(Object other) =>
      other is PageConfig &&
      enabled == other.enabled &&
      pageWidth == other.pageWidth &&
      pageHeight == other.pageHeight &&
      tolerance == other.tolerance;

  @override
  int get hashCode => Object.hash(enabled, pageWidth, pageHeight, tolerance);
}
