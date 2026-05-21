import 'package:flutter/foundation.dart';

/// Lightweight one-way bus so widgets outside `MapTab` can ask the map
/// camera to smart-zoom back to the initial "everyone fits" view.
///
/// Used when closing the contact profile sheet — the sheet lives at the
/// bottom of the bottom drawer, but the actual camera state belongs to
/// `MapTab` further up the tree. `MapTab` listens to [resetRequested]
/// in initState and calls its private `_resetToInitialZoom()` when the
/// counter ticks.
///
/// Singleton ValueNotifier of an int because we only need a "something
/// happened" pulse — the int value itself is meaningless.
class MapCameraSignals {
  MapCameraSignals._();

  static final ValueNotifier<int> resetRequested = ValueNotifier<int>(0);

  static void requestReset() {
    resetRequested.value = resetRequested.value + 1;
  }
}
