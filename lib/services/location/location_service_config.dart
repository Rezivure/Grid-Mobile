/// Simple configuration for location tracking.
/// Exposes only what the app needs without leaking plugin-specific details.
enum TrackingMode {
  /// High accuracy, frequent updates, higher battery usage.
  normal,

  /// Balanced accuracy and battery usage.
  batterySaver,
}

class LocationServiceConfig {
  final TrackingMode mode;
  final bool enableHeadless;
  final bool startOnBoot;

  const LocationServiceConfig({
    this.mode = TrackingMode.normal,
    this.enableHeadless = false,
    this.startOnBoot = false,
  });

  LocationServiceConfig copyWith({
    TrackingMode? mode,
    bool? enableHeadless,
    bool? startOnBoot,
  }) {
    return LocationServiceConfig(
      mode: mode ?? this.mode,
      enableHeadless: enableHeadless ?? this.enableHeadless,
      startOnBoot: startOnBoot ?? this.startOnBoot,
    );
  }

  @override
  String toString() =>
      'LocationServiceConfig(mode: $mode, headless: $enableHeadless, startOnBoot: $startOnBoot)';
}