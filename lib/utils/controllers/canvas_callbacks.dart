/// View-level callbacks injected into mode controllers when they are attached
/// to a canvas widget. These are UI concerns that cannot be wired at
/// controller-construction time because they reference widget-local state.
class CanvasCallbacks {
  const CanvasCallbacks({
    required this.scheduleRebuild,
    required this.onWarning,
    required this.getPencilPasteConfirm,
  });

  /// Request a coalesced widget rebuild at the next display frame.
  final void Function() scheduleRebuild;

  /// Show a transient warning banner on the canvas.
  final void Function(String message) onWarning;

  /// Returns the current pencil-paste-confirm setting from [SettingsNotifier].
  /// Called at gesture time so the controller does not hold a stale value.
  final bool Function() getPencilPasteConfirm;
}
