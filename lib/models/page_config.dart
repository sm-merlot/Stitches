/// Configuration for page mode — how a pattern is split into pages.
/// Persisted in the .stitches YAML file under the `pageMode:` key.
class PageConfig {
  final bool enabled;

  /// Number of columns (stitches) per page.
  final int pageWidth;

  /// Number of rows (stitches) per page.
  final int pageHeight;

  /// Maximum stitches a fuzzy edge can shift from the nominal boundary (0–3).
  /// 0 = straight edge, 3 = maximum randomisation.
  final int fuzzyAmount;

  const PageConfig({
    required this.enabled,
    required this.pageWidth,
    required this.pageHeight,
    required this.fuzzyAmount,
  });

  static const PageConfig disabled = PageConfig(
    enabled: false,
    pageWidth: 50,
    pageHeight: 50,
    fuzzyAmount: 2,
  );

  PageConfig copyWith({
    bool? enabled,
    int? pageWidth,
    int? pageHeight,
    int? fuzzyAmount,
  }) =>
      PageConfig(
        enabled: enabled ?? this.enabled,
        pageWidth: pageWidth ?? this.pageWidth,
        pageHeight: pageHeight ?? this.pageHeight,
        fuzzyAmount: fuzzyAmount ?? this.fuzzyAmount,
      );

  Map<String, dynamic> toYaml() => {
        'enabled': enabled,
        'pageWidth': pageWidth,
        'pageHeight': pageHeight,
        'fuzzyAmount': fuzzyAmount,
      };

  factory PageConfig.fromYaml(Map yaml) => PageConfig(
        enabled: yaml['enabled'] as bool? ?? false,
        pageWidth: yaml['pageWidth'] as int? ?? 50,
        pageHeight: yaml['pageHeight'] as int? ?? 50,
        fuzzyAmount: yaml['fuzzyAmount'] as int? ?? 2,
      );

  @override
  bool operator ==(Object other) =>
      other is PageConfig &&
      enabled == other.enabled &&
      pageWidth == other.pageWidth &&
      pageHeight == other.pageHeight &&
      fuzzyAmount == other.fuzzyAmount;

  @override
  int get hashCode => Object.hash(enabled, pageWidth, pageHeight, fuzzyAmount);
}
