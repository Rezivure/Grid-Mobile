import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:ui' show ImageFilter;
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:provider/provider.dart';

import 'package:grid_frontend/services/location_manager.dart';
import 'package:grid_frontend/styles/tokens.dart';
import 'package:grid_frontend/utilities/time_ago_formatter.dart';
import 'package:grid_frontend/widgets/grid/grid_mono.dart';
import 'package:grid_frontend/widgets/grid/grid_status_pill.dart';
import 'package:grid_frontend/widgets/user_avatar_bloc.dart';

/// Floating glass info card anchored above a tapped map pin. See spec §5.25.
///
/// Positioning is owned by the parent (MapTab); this widget keeps the
/// existing `Positioned` envelope so the call-site doesn't change.
class UserInfoBubble extends StatelessWidget {
  final String userId;
  final String userName;
  final LatLng position;
  final String? lastUpdate;
  final VoidCallback? onClose;

  const UserInfoBubble({
    super.key,
    required this.userId,
    required this.userName,
    required this.position,
    this.lastUpdate,
    this.onClose,
  });

  /// `null` when we don't know the user's own location yet (so the cell is
  /// hidden rather than showing a fake number).
  String? _formatDistance(LatLng? from, LatLng to) {
    if (from == null) return null;
    final meters = const Distance().as(LengthUnit.Meter, from, to);
    if (meters < 100) return '${meters.round()} m';
    if (meters < 1000) return '${(meters / 10).round() * 10} m';
    final km = meters / 1000;
    if (km < 10) return '${km.toStringAsFixed(1)} km';
    return '${km.round()} km';
  }

  String? _formatBearing(LatLng? from, LatLng to) {
    if (from == null) return null;
    final dLon = (to.longitude - from.longitude) * (math.pi / 180);
    final fromLat = from.latitude * (math.pi / 180);
    final toLat = to.latitude * (math.pi / 180);
    final y = math.sin(dLon) * math.cos(toLat);
    final x = math.cos(fromLat) * math.sin(toLat) -
        math.sin(fromLat) * math.cos(toLat) * math.cos(dLon);
    var bearing = math.atan2(y, x) * (180 / math.pi);
    bearing = (bearing + 360) % 360;
    const dirs = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    return dirs[((bearing + 22.5) ~/ 45) % 8];
  }

  void _copyCoordinates(BuildContext context, LatLng position) {
    final coordinates =
        '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
    Clipboard.setData(ClipboardData(text: coordinates));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Coordinates copied to clipboard'),
        backgroundColor: GridTokens.mint,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<bool> _showPrivacyWarning(BuildContext context) async {
    final shouldProceed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 340),
            decoration: BoxDecoration(
              color: GridTokens.surface,
              borderRadius: BorderRadius.circular(GridTokens.r2Xl),
              border: Border.all(color: GridTokens.hairlineStrong),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(
                      color: GridTokens.dangerSoft,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      color: GridTokens.danger,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Privacy Warning',
                    style: GoogleFonts.getFont(
                      'Geist',
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.02,
                      color: GridTokens.text,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'You are about to leave Grid and open this location in your maps application.\n\nThe location data will be shared with the external maps provider. Grid cannot ensure the privacy of this information once it leaves the app.',
                    style: GoogleFonts.getFont(
                      'Geist',
                      fontSize: 14,
                      color: GridTokens.text2,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: GridTokens.text,
                            side: const BorderSide(
                                color: GridTokens.hairlineStrong),
                            padding:
                                const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: GridTokens.mint,
                            foregroundColor: const Color(0xFF04201A),
                            padding:
                                const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
                            'Continue',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    return shouldProceed ?? false;
  }

  Future<void> _openInMaps(BuildContext context, LatLng position) async {
    try {
      String? mapChoice;

      if (Platform.isIOS) {
        // On iOS, show a dialog to choose between Apple Maps and Google Maps
        mapChoice = await showDialog<String>(
          context: context,
          builder: (BuildContext context) {
            return Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 260),
                decoration: BoxDecoration(
                  color: GridTokens.surface,
                  borderRadius: BorderRadius.circular(GridTokens.rXl),
                  border: Border.all(color: GridTokens.hairlineStrong),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Open in',
                        style: GoogleFonts.getFont(
                          'Geist',
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: GridTokens.text,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _MapChoiceTile(
                        label: 'Apple Maps',
                        icon: Icons.map_outlined,
                        iconColor: GridTokens.driving,
                        onTap: () => Navigator.of(context).pop('apple'),
                      ),
                      const SizedBox(height: 10),
                      _MapChoiceTile(
                        label: 'Google Maps',
                        icon: Icons.map_outlined,
                        iconColor: GridTokens.walking,
                        onTap: () => Navigator.of(context).pop('google'),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                        ),
                        child: Text(
                          'Cancel',
                          style: GoogleFonts.getFont(
                            'Geist',
                            color: GridTokens.text3,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );

        if (mapChoice == null) return;
      } else {
        // Android - use Google Maps directly
        mapChoice = 'google';
      }

      // Show privacy warning as the last step
      if (!context.mounted) return;
      if (!await _showPrivacyWarning(context)) {
        return;
      }

      // Now open the selected maps app
      if (mapChoice == 'apple') {
        // Apple Maps URL scheme
        final appleMapsUrl = Uri.parse(
            'maps://?q=${position.latitude},${position.longitude}');

        if (await canLaunchUrl(appleMapsUrl)) {
          await launchUrl(appleMapsUrl);
        } else {
          // Fallback to web-based Apple Maps
          final webAppleMapsUrl = Uri.parse(
              'https://maps.apple.com/?q=${position.latitude},${position.longitude}');
          await launchUrl(webAppleMapsUrl,
              mode: LaunchMode.externalApplication);
        }
      } else {
        // Google Maps
        if (Platform.isIOS) {
          // iOS Google Maps
          final googleMapsAppUrl = Uri.parse(
              'comgooglemaps://?q=${position.latitude},${position.longitude}');

          if (await canLaunchUrl(googleMapsAppUrl)) {
            await launchUrl(googleMapsAppUrl);
          } else {
            // Fallback to web
            final googleMapsWebUrl = Uri.parse(
                'https://www.google.com/maps/search/?api=1&query=${position.latitude},${position.longitude}');
            await launchUrl(googleMapsWebUrl,
                mode: LaunchMode.externalApplication);
          }
        } else {
          // Android Google Maps
          final googleMapsUrl = Uri.parse(
              'geo:${position.latitude},${position.longitude}?q=${position.latitude},${position.longitude}');

          if (await canLaunchUrl(googleMapsUrl)) {
            await launchUrl(googleMapsUrl);
          } else {
            // Fallback to web
            final googleMapsWebUrl = Uri.parse(
                'https://www.google.com/maps/search/?api=1&query=${position.latitude},${position.longitude}');
            await launchUrl(googleMapsWebUrl,
                mode: LaunchMode.externalApplication);
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not open maps application'),
            backgroundColor: GridTokens.danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  String _formatCoordinates(LatLng p) {
    final lat = p.latitude;
    final lng = p.longitude;
    final latStr = '${lat.abs().toStringAsFixed(4)}° ${lat >= 0 ? 'N' : 'S'}';
    final lngStr = '${lng.abs().toStringAsFixed(4)}° ${lng >= 0 ? 'E' : 'W'}';
    return '$latStr  $lngStr';
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screenWidth = media.size.width;
    // Width up to 340, with at least 16pt margin per side. Centered.
    final bubbleWidth =
        (screenWidth - 32).clamp(260.0, 340.0).toDouble();
    // Sit well below the top-of-map "SHARING WITH N" pill (which is at
    // SafeArea + 60 + ~30 tall). Push the bubble below that comfortably.
    final topOffset = media.padding.top + 96;
    final myLocation =
        Provider.of<LocationManager>(context, listen: false).currentLatLng;
    final distanceLabel = _formatDistance(myLocation, position);
    final bearingLabel = _formatBearing(myLocation, position);
    final updatedLabel = lastUpdate == null
        ? null
        : TimeAgoFormatter.format(lastUpdate);

    return Positioned(
      top: topOffset,
      left: (screenWidth - bubbleWidth) / 2,
      width: bubbleWidth,
      child: Material(
        color: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Glass card ────────────────────────────────────────
            ClipRRect(
              borderRadius: BorderRadius.circular(GridTokens.rLg),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: GridTokens.surface.withOpacity(0.95),
                    borderRadius: BorderRadius.circular(GridTokens.rLg),
                    border: Border.all(
                      color: GridTokens.hairlineStrong,
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.55),
                        blurRadius: 32,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _IdentityRow(
                          userId: userId,
                          userName: userName,
                          coordinatesLabel: _formatCoordinates(position),
                          onCopyCoordinates: () =>
                              _copyCoordinates(context, position),
                          onClose: onClose,
                        ),
                        const SizedBox(height: 12),
                        _StatusRow(
                          distance: distanceLabel,
                          bearing: bearingLabel,
                          updated: updatedLabel,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _MiniBtn(
                                icon: Icons.chat_bubble_outline_rounded,
                                label: 'Chat',
                                // TODO: needs chat surface
                                onTap: null,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: _MiniBtn(
                                icon: Icons.history_rounded,
                                label: 'History',
                                // TODO: needs location-history entry point
                                onTap: null,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: _MiniBtn(
                                icon: Icons.near_me_rounded,
                                label: 'Route',
                                onTap: () => _openInMaps(context, position),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // ── Tail triangle pointing down at the pin ───────────
            CustomPaint(
              size: const Size(18, 9),
              painter: _BubbleTailPainter(),
            ),
          ],
        ),
      ),
    );
  }
}

class _IdentityRow extends StatelessWidget {
  const _IdentityRow({
    required this.userId,
    required this.userName,
    required this.coordinatesLabel,
    required this.onCopyCoordinates,
    required this.onClose,
  });

  final String userId;
  final String userName;
  final String coordinatesLabel;
  final VoidCallback onCopyCoordinates;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Avatar 42 with live status dot.
        SizedBox(
          width: 42,
          height: 42,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              ClipOval(
                child: SizedBox(
                  width: 42,
                  height: 42,
                  child: UserAvatarBloc(
                    userId: userId,
                    size: 42,
                  ),
                ),
              ),
              Positioned(
                right: -1,
                bottom: -1,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: GridTokens.mint,
                    shape: BoxShape.circle,
                    border: Border.all(color: GridTokens.surface, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: GridTokens.mint.withOpacity(0.6),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        // Identity column.
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.getFont(
                        'Geist',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.01,
                        color: GridTokens.text,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const GridLiveBadge(),
                ],
              ),
              const SizedBox(height: 2),
              InkWell(
                onTap: onCopyCoordinates,
                borderRadius: BorderRadius.circular(GridTokens.rSm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: GridMono(
                    coordinatesLabel,
                    size: 10.5,
                    uppercase: false,
                    color: GridTokens.text3,
                    letterSpacing: 0.04,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        // Close (30×30).
        _CloseButton(onTap: onClose),
      ],
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: GridTokens.surface2,
            shape: BoxShape.circle,
            border: Border.all(color: GridTokens.hairline, width: 1),
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.close_rounded,
            size: 16,
            color: GridTokens.text2,
          ),
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.distance,
    required this.bearing,
    required this.updated,
  });

  /// All three are optional: we only render the cells we have real data for.
  /// Driving/walking pills were intentionally removed — the app doesn't pass
  /// speed through `UserLocation` today, so any motion label here would be
  /// made up.
  final String? distance;
  final String? bearing;
  final String? updated;

  @override
  Widget build(BuildContext context) {
    final cells = <Widget>[];
    if (distance != null) {
      cells.add(
        _MonoCell(
          primary: distance!,
          secondary: bearing ?? '',
        ),
      );
    }
    if (updated != null) {
      cells.add(
        _MonoCell(
          primary: 'updated',
          secondary: updated!,
        ),
      );
    }
    if (cells.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        for (var i = 0; i < cells.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(child: cells[i]),
        ],
      ],
    );
  }
}

class _MonoCell extends StatelessWidget {
  const _MonoCell({required this.primary, required this.secondary});

  final String primary;
  final String secondary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: GridTokens.surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: GridTokens.hairline, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: GridMono(
              primary,
              size: 10,
              uppercase: false,
              color: GridTokens.text,
              letterSpacing: 0.04,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: GridMono(
              secondary,
              size: 10,
              uppercase: false,
              color: GridTokens.text3,
              letterSpacing: 0.04,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniBtn extends StatelessWidget {
  const _MiniBtn({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final fg = enabled ? GridTokens.text : GridTokens.text3;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(GridTokens.rMd),
        child: Ink(
          height: 38,
          decoration: BoxDecoration(
            color: GridTokens.surface2,
            borderRadius: BorderRadius.circular(GridTokens.rMd),
            border: Border.all(color: GridTokens.hairline, width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 5),
              Text(
                label,
                style: GoogleFonts.getFont(
                  'Geist',
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.005,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapChoiceTile extends StatelessWidget {
  const _MapChoiceTile({
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: GridTokens.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: GridTokens.hairline),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.getFont(
                'Geist',
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: GridTokens.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BubbleTailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..color = GridTokens.surface.withOpacity(0.95)
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = GridTokens.hairlineStrong
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();

    canvas.drawPath(path, fill);
    // Draw only the two slanted edges so the top stays continuous with the
    // card body above (no visible seam between card and tail).
    final edge = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0);
    canvas.drawPath(edge, stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
