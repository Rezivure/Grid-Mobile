import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:ui';

class IconSelectionWheel extends StatefulWidget {
  final Offset position;
  final Function(IconType) onIconSelected;
  final VoidCallback onCancel;

  const IconSelectionWheel({
    Key? key,
    required this.position,
    required this.onIconSelected,
    required this.onCancel,
  }) : super(key: key);

  @override
  State<IconSelectionWheel> createState() => _IconSelectionWheelState();
}

class _IconSelectionWheelState extends State<IconSelectionWheel> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  IconType? _hoveredIcon;
  
  // Define available icons
  static const List<IconType> icons = [
    IconType.pin,
    IconType.warning,
    IconType.food,
    IconType.car,
    IconType.home,
    IconType.star,
    IconType.heart,
    IconType.flag,
  ];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const double wheelRadius = 90.0;
    const double iconSize = 44.0;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Stack(
      children: [
        // Blurred backdrop
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onCancel,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
              child: Container(
                color: Colors.black.withOpacity(0.1),
              ),
            ),
          ),
        ),
        // The wheel
        Positioned(
          left: widget.position.dx - wheelRadius - iconSize/2,
          top: widget.position.dy - wheelRadius - iconSize/2,
          child: AnimatedBuilder(
            animation: _scaleAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _scaleAnimation.value,
                child: SizedBox(
                  width: (wheelRadius + iconSize/2) * 2,
                  height: (wheelRadius + iconSize/2) * 2,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Glass morphism background
                      ClipRRect(
                        borderRadius: BorderRadius.circular(wheelRadius + 10),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            width: wheelRadius * 2 + 20,
                            height: wheelRadius * 2 + 20,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  colorScheme.surface.withOpacity(isDark ? 0.2 : 0.9),
                                  colorScheme.surface.withOpacity(isDark ? 0.1 : 0.8),
                                ],
                              ),
                              border: Border.all(
                                color: colorScheme.outline.withOpacity(0.1),
                                width: 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.15),
                                  blurRadius: 30,
                                  spreadRadius: 10,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Center tap location indicator with pulse
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colorScheme.primary.withOpacity(0.1),
                          border: Border.all(
                            color: colorScheme.primary.withOpacity(0.3),
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: colorScheme.primary.withOpacity(0.6),
                            ),
                          ),
                        ),
                      ),
                      // Icons arranged in circle
                      ...icons.asMap().entries.map((entry) {
                        final index = entry.key;
                        final iconType = entry.value;
                        final angle = (index * 2 * math.pi) / icons.length - math.pi / 2;
                        final isHovered = _hoveredIcon == iconType;
                        
                        return Positioned(
                          left: wheelRadius + math.cos(angle) * wheelRadius - iconSize/2 + iconSize/2,
                          top: wheelRadius + math.sin(angle) * wheelRadius - iconSize/2 + iconSize/2,
                          child: GestureDetector(
                            onTapDown: (_) {
                              setState(() {
                                _hoveredIcon = iconType;
                              });
                              // Call selection immediately on tap down for instant response
                              widget.onIconSelected(iconType);
                            },
                            onTapUp: (_) {
                              // No longer needed here since we handle on tap down
                            },
                            onTapCancel: () {
                              setState(() {
                                _hoveredIcon = null;
                              });
                            },
                            child: Transform.scale(
                              scale: isHovered ? 1.1 : 1.0,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 50),
                                width: iconSize,
                                height: iconSize,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isHovered 
                                    ? colorScheme.primary
                                    : colorScheme.surface,
                                  border: isHovered ? Border.all(
                                    color: colorScheme.onPrimary.withOpacity(0.3),
                                    width: 1,
                                  ) : null,
                                  boxShadow: [
                                    BoxShadow(
                                      color: isHovered 
                                        ? colorScheme.primary.withOpacity(0.4)
                                        : Colors.black.withOpacity(0.08),
                                      blurRadius: isHovered ? 16 : 6,
                                      offset: Offset(0, isHovered ? 4 : 2),
                                      spreadRadius: isHovered ? 2 : 0,
                                    ),
                                    if (!isHovered && !isDark)
                                      BoxShadow(
                                        color: Colors.white.withOpacity(0.8),
                                        blurRadius: 3,
                                        offset: const Offset(0, -1),
                                        spreadRadius: 0,
                                      ),
                                  ],
                                ),
                                child: Icon(
                                  _getIconData(iconType),
                                  size: 22,
                                  color: isHovered 
                                    ? colorScheme.onPrimary
                                    : colorScheme.primary,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  IconData _getIconData(IconType type) {
    switch (type) {
      case IconType.pin:
        return Icons.location_on;
      case IconType.warning:
        return Icons.warning;
      case IconType.food:
        return Icons.restaurant;
      case IconType.car:
        return Icons.directions_car;
      case IconType.home:
        return Icons.home;
      case IconType.star:
        return Icons.star;
      case IconType.heart:
        return Icons.favorite;
      case IconType.flag:
        return Icons.flag;
    }
  }
}

enum IconType {
  pin,
  warning,
  food,
  car,
  home,
  star,
  heart,
  flag,
}