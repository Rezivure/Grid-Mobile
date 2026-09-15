/// Simple configuration for location tracking.
/// Exposes only what the app needs without leaking plugin-specific details.
/// Service-layer tiers behind the user-facing `Sharing mode` setting.
/// Names are historical; see [SharingMode] for the labels users see.
enum TrackingMode {
  /// "Balanced" — moderate accuracy and battery usage. The default.
  normal,

  /// "Light" — lowest accuracy, longest intervals, least battery.
  batterySaver,

  /// "Live" — highest accuracy and update rate, heaviest battery.
  live,
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