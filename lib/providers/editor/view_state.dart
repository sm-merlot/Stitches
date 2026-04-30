part of 'editor_provider.dart';

// ─── ViewState ────────────────────────────────────────────────────────────────

/// Last-known canvas view position — written on pointer-up, read on file open.
/// Scale == 0 means no saved position (use AidaWidget default).
class ViewState {
  final double panX;
  final double panY;
  final double scale;

  const ViewState({this.panX = 0, this.panY = 0, this.scale = 0});

  ViewState copyWith({double? panX, double? panY, double? scale}) => ViewState(
        panX: panX ?? this.panX,
        panY: panY ?? this.panY,
        scale: scale ?? this.scale,
      );
}
