import 'package:flutter/material.dart';

/// How a layer's colours are composited onto the layers below it.
///
/// For all non-Normal modes the blend is applied at full strength first, then
/// the result is lerped back to the base colour by [apply]'s opacity parameter,
/// so opacity 0 always equals "fully transparent / base shows through" and
/// opacity 1 equals "full blend effect".
enum LayerBlendMode {
  normal,
  screen,
  multiply,
  add,
  overlay;

  // ── Blend application ────────────────────────────────────────────────────

  /// Composite [overlay] onto [base] according to this blend mode, scaled by
  /// [opacity] (0 = fully base, 1 = full blend effect).
  Color apply(Color base, Color overlay, double opacity) {
    if (this == LayerBlendMode.normal) {
      return Color.lerp(base, overlay, opacity)!;
    }
    final blended = _blend(base, overlay);
    return Color.lerp(base, blended, opacity)!;
  }

  Color _blend(Color a, Color b) => switch (this) {
        LayerBlendMode.normal => Color.lerp(a, b, 1.0)!,
        LayerBlendMode.screen => Color.from(
            alpha: 1.0,
            red: 1.0 - (1.0 - a.r) * (1.0 - b.r),
            green: 1.0 - (1.0 - a.g) * (1.0 - b.g),
            blue: 1.0 - (1.0 - a.b) * (1.0 - b.b),
          ),
        LayerBlendMode.multiply => Color.from(
            alpha: 1.0,
            red: a.r * b.r,
            green: a.g * b.g,
            blue: a.b * b.b,
          ),
        LayerBlendMode.add => Color.from(
            alpha: 1.0,
            red: (a.r + b.r).clamp(0.0, 1.0),
            green: (a.g + b.g).clamp(0.0, 1.0),
            blue: (a.b + b.b).clamp(0.0, 1.0),
          ),
        LayerBlendMode.overlay => Color.from(
            alpha: 1.0,
            red: _overlayChannel(a.r, b.r),
            green: _overlayChannel(a.g, b.g),
            blue: _overlayChannel(a.b, b.b),
          ),
      };

  static double _overlayChannel(double a, double b) =>
      a < 0.5 ? 2 * a * b : 1 - 2 * (1 - a) * (1 - b);

  // ── Serialization ────────────────────────────────────────────────────────

  String get yamlKey => name; // 'normal', 'screen', etc.

  static LayerBlendMode fromYaml(String? key) => LayerBlendMode.values
      .firstWhere((m) => m.name == key, orElse: () => LayerBlendMode.normal);

  // ── Display ──────────────────────────────────────────────────────────────

  String get displayName => switch (this) {
        LayerBlendMode.normal => 'Normal',
        LayerBlendMode.screen => 'Screen',
        LayerBlendMode.multiply => 'Multiply',
        LayerBlendMode.add => 'Add',
        LayerBlendMode.overlay => 'Overlay',
      };
}
