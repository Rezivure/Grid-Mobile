import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:provider/provider.dart';

import '../../services/location_manager.dart';
import '../../styles/tokens.dart';
import '../../styles/grid_colors.dart';
import '../../widgets/grid/grid_button.dart';
import '../../widgets/grid/grid_mono.dart';
import '../map/grid_map_style.dart';

/// Returned by [HomeLocationPickerScreen] — pairs the chosen lat/lng with
/// the geofence radius the user selected for it.
class HomeLocationResult {
  const HomeLocationResult({required this.latLng, required this.radiusMeters});
  final ll.LatLng latLng;
  final double radiusMeters;
}

/// Screen that lets the user pick the lat/lng of their "home" and the
/// geofence radius around it. A mint pin is anchored to the screen center
/// and the radius circle is drawn around it live, so panning the map keeps
/// the pin+circle pinned to the center while the world moves beneath them.
class HomeLocationPickerScreen extends StatefulWidget {
  const HomeLocationPickerScreen({
    super.key,
    this.initialRadiusMeters = 25,
  });

  final double initialRadiusMeters;

  @override
  State<HomeLocationPickerScreen> createState() =>
      _HomeLocationPickerScreenState();
}

class _HomeLocationPickerScreenState extends State<HomeLocationPickerScreen>
    with SingleTickerProviderStateMixin {
  ml.MapLibreMapController? _mlController;
  late final AnimationController _tick;
  late final Animation<double> _pulseAnimation;
  bool _isInteracting = false;
  bool _confirming = false;
  bool? _isDarkStyle;
  String? _styleJson;

  late double _radiusMeters = widget.initialRadiusMeters.clamp(_minRadius, _maxRadius);

  // Floor at 50m: platform geofence accuracy is ~50–100m on most phones,
  // and HomeGeofenceService clamps the monitored region to this floor
  // anyway. Letting the slider go lower just makes the visual circle lie.
  static const double _minRadius = 50;
  static const double _maxRadius = 300;

  // Fallback if the user has no last known location yet.
  static const ll.LatLng _fallbackCenter = ll.LatLng(37.7749, -122.4194);

  @override
  void initState() {
    super.initState();
    // Continuously running ticker drives both the pin pulse and the live
    // radius-circle redraw while the camera is moving (maplibre doesn't
    // expose a per-frame camera callback).
    _tick = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
    _pulseAnimation = CurvedAnimation(
      parent: _tick,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _tick.dispose();
    super.dispose();
  }

  ll.LatLng _resolveInitialCenter() {
    final locationManager =
        Provider.of<LocationManager>(context, listen: false);
    return locationManager.currentLatLng ?? _fallbackCenter;
  }

  Future<void> _confirm() async {
    if (_confirming) return;
    final controller = _mlController;
    if (controller == null) return;

    setState(() => _confirming = true);
    final target = controller.cameraPosition?.target;
    if (target == null) {
      setState(() => _confirming = false);
      return;
    }

    Navigator.of(context).pop<HomeLocationResult>(
      HomeLocationResult(
        latLng: ll.LatLng(target.latitude, target.longitude),
        radiusMeters: _radiusMeters,
      ),
    );
  }

  /// Web Mercator resolution at the current camera target — meters covered
  /// by a single screen pixel. Used to draw the geofence circle at the
  /// correct on-screen size for the current zoom.
  double _metersPerPixel() {
    final cam = _mlController?.cameraPosition;
    if (cam == null) return 0;
    final lat = cam.target.latitude * math.pi / 180.0;
    final zoom = cam.zoom;
    return 78271.516 * math.cos(lat) / math.pow(2, zoom);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    if (_isDarkStyle != isDark) {
      _isDarkStyle = isDark;
      _styleJson = buildGridMapStyle(dark: isDark);
    }

    final initialCenter = _resolveInitialCenter();

    return Scaffold(
      backgroundColor: context.gridColors.bg,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leadingWidth: 64,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: GridNavIconButton(
              icon: Icons.arrow_back_ios_new_rounded,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        ),
        title: Text(
          'Set home location',
          style: GoogleFonts.getFont(
            'Geist',
            color: context.gridColors.text,
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.01,
          ),
        ),
      ),
      body: Stack(
        children: [
          // Map fills the entire screen behind the chrome.
          Positioned.fill(
            child: ml.MapLibreMap(
              styleString: _styleJson!,
              initialCameraPosition: ml.CameraPosition(
                target: ml.LatLng(
                  initialCenter.latitude,
                  initialCenter.longitude,
                ),
                zoom: 16,
              ),
              myLocationEnabled: false,
              trackCameraPosition: true,
              rotateGesturesEnabled: false,
              tiltGesturesEnabled: false,
              minMaxZoomPreference:
                  const ml.MinMaxZoomPreference(3.5, 19),
              attributionButtonPosition:
                  ml.AttributionButtonPosition.bottomLeft,
              onMapCreated: (controller) {
                _mlController = controller;
              },
              onCameraTrackingDismissed: () {},
              onCameraIdle: () {
                if (_isInteracting && mounted) {
                  setState(() => _isInteracting = false);
                }
              },
              onMapClick: (_, __) {},
            ),
          ),

          // Subtle scrim so the pin and chrome read clearly against the map.
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      context.gridColors.bg.withOpacity(0.55),
                      Colors.transparent,
                      Colors.transparent,
                      context.gridColors.bg.withOpacity(0.65),
                    ],
                    stops: const [0.0, 0.15, 0.5, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // Detect drags so the pin can "lift" slightly while panning.
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) {
                if (!_isInteracting && mounted) {
                  setState(() => _isInteracting = true);
                }
              },
              child: const SizedBox.expand(),
            ),
          ),

          // Centered radius circle — redrawn every tick so it stays sized
          // correctly while the user zooms / pans.
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _tick,
                builder: (context, _) {
                  final mpp = _metersPerPixel();
                  if (mpp <= 0) return const SizedBox.shrink();
                  final radiusPx = _radiusMeters / mpp;
                  final diameter = radiusPx * 2;
                  if (diameter < 4) return const SizedBox.shrink();
                  return Center(
                    child: SizedBox(
                      width: diameter,
                      height: diameter,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: context.gridColors.mint.withOpacity(0.12),
                          border: Border.all(
                            color: context.gridColors.mint.withOpacity(0.65),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // Centered pulsing mint pin overlay.
          Positioned.fill(
            child: IgnorePointer(
              child: Align(
                alignment: Alignment.center,
                child: _CenterPin(
                  pulse: _pulseAnimation,
                  lifted: _isInteracting,
                ),
              ),
            ),
          ),

          // Helper caption near the top.
          Positioned(
            top: MediaQuery.of(context).padding.top + 72,
            left: 24,
            right: 24,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: context.gridColors.surface.withOpacity(0.92),
                    borderRadius:
                        BorderRadius.circular(GridTokens.rMd),
                    border:
                        Border.all(color: context.gridColors.hairlineStrong),
                  ),
                  child: Text(
                    'Pan the map until the pin sits over your home.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.getFont(
                      'Geist',
                      color: context.gridColors.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.005,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Bottom card: radius slider + confirm button.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  decoration: BoxDecoration(
                    color: context.gridColors.surface.withOpacity(0.96),
                    borderRadius:
                        BorderRadius.circular(GridTokens.rLg),
                    border:
                        Border.all(color: context.gridColors.hairlineStrong),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.radio_button_checked_rounded,
                            size: 16,
                            color: context.gridColors.mint,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Geofence radius',
                            style: GoogleFonts.getFont(
                              'Geist',
                              color: context.gridColors.text,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.01,
                            ),
                          ),
                          const Spacer(),
                          GridMono(
                            '${_radiusMeters.round()} M',
                            size: 11,
                            letterSpacing: 0.08,
                            color: context.gridColors.mint,
                          ),
                        ],
                      ),
                      SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 3,
                          activeTrackColor: context.gridColors.mint,
                          inactiveTrackColor: context.gridColors.hairlineStrong,
                          thumbColor: context.gridColors.mint,
                          overlayColor:
                              context.gridColors.mint.withOpacity(0.16),
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 9,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 18,
                          ),
                        ),
                        child: Slider(
                          value: _radiusMeters,
                          min: _minRadius,
                          max: _maxRadius,
                          divisions: ((_maxRadius - _minRadius) / 5).round(),
                          onChanged: (v) =>
                              setState(() => _radiusMeters = v),
                        ),
                      ),
                      const SizedBox(height: 8),
                      GridButton(
                        label:
                            _confirming ? 'Saving…' : 'Confirm home location',
                        icon: Icons.check_rounded,
                        onPressed: _confirming ? null : _confirm,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Mint pin with a pulsing halo. Stays centered via the parent `Align`.
class _CenterPin extends StatelessWidget {
  const _CenterPin({required this.pulse, required this.lifted});

  final Animation<double> pulse;
  final bool lifted;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, _) {
        // pulse value 0..1; turn into expanding/fading halo.
        final t = pulse.value;
        final haloScale = 1.0 + (t * 1.6);
        final haloOpacity = (1.0 - t) * 0.45;
        const dotSize = 22.0;
        const haloSize = 48.0;

        return SizedBox(
          width: haloSize * 2,
          height: haloSize * 2,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Pulsing halo
              IgnorePointer(
                child: Opacity(
                  opacity: haloOpacity.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: haloScale,
                    child: Container(
                      width: haloSize,
                      height: haloSize,
                      decoration: BoxDecoration(
                        color: context.gridColors.mintSoft,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),

              // Drop-shadow stalk that grows slightly while dragging.
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                width: lifted ? 6 : 4,
                height: lifted ? 10 : 4,
                margin: EdgeInsets.only(top: lifted ? 38 : dotSize + 2),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),

              // Lifted core dot with mint ring + white center.
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                transform: Matrix4.translationValues(
                  0,
                  lifted ? -16 : 0,
                  0,
                ),
                width: dotSize,
                height: dotSize,
                decoration: BoxDecoration(
                  color: context.gridColors.mint,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: context.gridColors.mint.withOpacity(0.55),
                      blurRadius: 16,
                      spreadRadius: 1,
                    ),
                    BoxShadow(
                      color: Colors.black.withOpacity(0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
