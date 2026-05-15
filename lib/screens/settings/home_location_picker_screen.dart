import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:provider/provider.dart';

import '../../services/location_manager.dart';
import '../../styles/tokens.dart';
import '../../widgets/grid/grid_button.dart';
import '../map/grid_map_style.dart';

/// Screen that lets the user pick the lat/lng of their "home" by panning a
/// MapLibre map. A mint pin is anchored to the screen center as a visual
/// indicator; the user moves the map until the pin overlays their home, then
/// taps "Confirm home location". The lat/lng of the final camera target is
/// returned to the caller via `Navigator.pop`.
class HomeLocationPickerScreen extends StatefulWidget {
  const HomeLocationPickerScreen({super.key});

  @override
  State<HomeLocationPickerScreen> createState() =>
      _HomeLocationPickerScreenState();
}

class _HomeLocationPickerScreenState extends State<HomeLocationPickerScreen>
    with SingleTickerProviderStateMixin {
  ml.MapLibreMapController? _mlController;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;
  bool _isInteracting = false;
  bool _confirming = false;
  bool? _isDarkStyle;
  String? _styleJson;

  // Fallback if the user has no last known location yet.
  static const ll.LatLng _fallbackCenter = ll.LatLng(37.7749, -122.4194);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
    _pulseAnimation = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
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

    Navigator.of(context).pop<ll.LatLng>(
      ll.LatLng(target.latitude, target.longitude),
    );
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
      backgroundColor: GridTokens.bg,
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
            color: GridTokens.text,
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
                zoom: 15.5,
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
                      GridTokens.bg.withOpacity(0.55),
                      Colors.transparent,
                      Colors.transparent,
                      GridTokens.bg.withOpacity(0.65),
                    ],
                    stops: const [0.0, 0.15, 0.55, 1.0],
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
                    color: GridTokens.surface.withOpacity(0.92),
                    borderRadius:
                        BorderRadius.circular(GridTokens.rMd),
                    border:
                        Border.all(color: GridTokens.hairlineStrong),
                  ),
                  child: Text(
                    'Pan the map until the pin sits over your home.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.getFont(
                      'Geist',
                      color: GridTokens.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.005,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Bottom confirm button.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
                child: GridButton(
                  label:
                      _confirming ? 'Saving…' : 'Confirm home location',
                  icon: Icons.check_rounded,
                  onPressed: _confirming ? null : _confirm,
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
                      decoration: const BoxDecoration(
                        color: GridTokens.mintSoft,
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
                  color: GridTokens.mint,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: GridTokens.mint.withOpacity(0.55),
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
