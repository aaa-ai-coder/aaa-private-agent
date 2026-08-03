class FeatureFlags {
  FeatureFlags._();

  static const bool floatingOverlayEnabled = true;

  /// Whether the floating bubble should appear when the app is in the
  /// background. User-controlled via Settings → Floating Overlay Window.
  static bool floatingIconEnabled = true;
}
