import 'package:flutter/material.dart';
import 'package:random_avatar/random_avatar.dart';
import 'package:grid_frontend/utilities/time_ago_formatter.dart';
import 'user_avatar_bloc.dart';

class UserMapMarker extends StatefulWidget {
  final String userId;
  final bool isSelected;
  final bool showPulse;
  final String? timestamp;

  const UserMapMarker({
    Key? key,
    required this.userId,
    this.isSelected = false,
    this.showPulse = true,
    this.timestamp,
  }) : super(key: key);

  @override
  _UserMapMarkerState createState() => _UserMapMarkerState();
}

class _UserMapMarkerState extends State<UserMapMarker>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _selectionController;
  late AnimationController _bounceController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _shadowAnimation;
  late Animation<double> _bounceAnimation;

  @override
  void initState() {
    super.initState();

    // Pulse animation controller
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    // Selection animation controller
    _selectionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    // Bounce animation controller
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    // Smooth pulse animation with easing
    _pulseAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    // Scale animation for selection
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.15,
    ).animate(CurvedAnimation(
      parent: _selectionController,
      curve: Curves.elasticOut,
    ));

    // Shadow animation for selection
    _shadowAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _selectionController,
      curve: Curves.easeOut,
    ));

    // Bounce animation sequence
    _bounceAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: -30.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 35.0,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: -30.0, end: 0.0)
            .chain(CurveTween(curve: Curves.bounceOut)),
        weight: 65.0,
      ),
    ]).animate(_bounceController);

    if (widget.showPulse) {
      _pulseController.repeat();
    }

    if (widget.isSelected) {
      _selectionController.forward();
      // Trigger bounce animation when initially selected
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _bounceController.forward();
      });
    }
  }

  @override
  void didUpdateWidget(UserMapMarker oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (widget.isSelected != oldWidget.isSelected) {
      if (widget.isSelected) {
        _selectionController.forward();
        // Trigger bounce animation when becoming selected
        _bounceController.reset();
        _bounceController.forward();
      } else {
        _selectionController.reverse();
      }
    }

    if (widget.showPulse != oldWidget.showPulse) {
      if (widget.showPulse) {
        _pulseController.repeat();
      } else {
        _pulseController.stop();
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _selectionController.dispose();
    _bounceController.dispose();
    super.dispose();
  }

  Color _getStatusColor(ColorScheme colorScheme) {
    if (widget.timestamp == null) {
      return Colors.green; // Default to green if no timestamp
    }

    final timeAgo = TimeAgoFormatter.format(widget.timestamp);
    
    if (timeAgo == 'Just now' || timeAgo.contains('s ago')) {
      return colorScheme.primary; // Green for active (seconds)
    } else if (timeAgo.contains('m ago')) {
      // Parse minutes
      final minutes = int.tryParse(timeAgo.split(' ')[0]) ?? 0;
      if (minutes <= 10) {
        return colorScheme.primary; // Still green for <= 10 minutes
      } else {
        return Colors.orange; // Orange for > 10 minutes
      }
    } else if (timeAgo.contains('h ago')) {
      return Colors.orange; // Orange for hours
    } else if (timeAgo.contains('d ago')) {
      return Colors.red; // Red for days
    } else {
      return colorScheme.onSurface.withOpacity(0.4); // Grey for offline/very old
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final username = widget.userId.split(':')[0].replaceFirst('@', '');
    final statusColor = _getStatusColor(colorScheme);

    return AnimatedBuilder(
      animation: Listenable.merge([_pulseAnimation, _scaleAnimation, _bounceAnimation]),
      builder: (context, child) {
        return Transform.translate(
          // Offset up by pin height (50/2 + 8) + bounce animation
          offset: Offset(0, -33 + _bounceAnimation.value),
          child: Transform.scale(
            scale: _scaleAnimation.value,
            child: SizedBox(
              width: 100,
              height: 100,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                // Pulse rings
                if (widget.showPulse) ...[
                  // Outer pulse
                  Positioned(
                    top: 25,
                    child: Container(
                      width: 50 + (30 * _pulseAnimation.value),
                      height: 50 + (30 * _pulseAnimation.value),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: statusColor.withOpacity(0.2 * (1 - _pulseAnimation.value)),
                      ),
                    ),
                  ),
                  // Inner pulse
                  Positioned(
                    top: 25,
                    child: Container(
                      width: 50 + (15 * _pulseAnimation.value),
                      height: 50 + (15 * _pulseAnimation.value),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: statusColor.withOpacity(0.3 * (1 - _pulseAnimation.value)),
                      ),
                    ),
                  ),
                ],
                
                // Pin shape with 3D effect
                Positioned(
                  top: 25,
                  child: Column(
                    children: [
                      // Main circular container with 3D effect
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            // Bottom shadow for depth
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                              spreadRadius: 1,
                            ),
                            // Colored glow when selected
                            if (widget.isSelected)
                              BoxShadow(
                                color: statusColor.withOpacity(0.4),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                          ],
                        ),
                        child: Stack(
                          children: [
                            // Background with gradient for 3D effect
                            Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Colors.white,
                                    Colors.grey[100]!,
                                  ],
                                ),
                                border: Border.all(
                                  color: Colors.white,
                                  width: 3,
                                ),
                              ),
                            ),
                            // Inner shadow for depth
                            Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withOpacity(0.05),
                                  ],
                                ),
                              ),
                            ),
                            // Avatar container
                            Center(
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: widget.isSelected 
                                        ? statusColor.withOpacity(0.3)
                                        : Colors.grey.withOpacity(0.1),
                                    width: 1,
                                  ),
                                ),
                                child: ClipOval(
                                  child: UserAvatarBloc(
                                    key: ValueKey('avatar_${widget.userId}'),
                                    userId: widget.userId,
                                    size: 44,
                                  ),
                                ),
                              ),
                            ),
                            // Top highlight for 3D effect
                            Positioned(
                              top: 3,
                              left: 10,
                              child: Container(
                                width: 15,
                                height: 8,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  color: Colors.white.withOpacity(0.6),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Pin point (triangle)
                      CustomPaint(
                        size: const Size(16, 8),
                        painter: _PinPointPainter(
                          color: Colors.white,
                          shadowColor: Colors.black.withOpacity(0.2),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        );
      },
    );
  }
}

// Custom painter for the pin point
class _PinPointPainter extends CustomPainter {
  final Color color;
  final Color shadowColor;

  _PinPointPainter({
    required this.color,
    required this.shadowColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final shadowPaint = Paint()
      ..color = shadowColor
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();

    // Draw shadow
    canvas.save();
    canvas.translate(0, 1);
    canvas.drawPath(path, shadowPaint);
    canvas.restore();

    // Draw pin point
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
