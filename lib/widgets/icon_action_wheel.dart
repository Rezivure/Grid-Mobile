import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:ui';

class IconActionWheel extends StatefulWidget {
  final Offset position;
  final VoidCallback onDetails;
  final VoidCallback onDelete;
  final VoidCallback onZoom;
  final VoidCallback onMove;
  final VoidCallback onCancel;

  const IconActionWheel({
    Key? key,
    required this.position,
    required this.onDetails,
    required this.onDelete,
    required this.onZoom,
    required this.onMove,
    required this.onCancel,
  }) : super(key: key);

  @override
  State<IconActionWheel> createState() => _IconActionWheelState();
}

class _IconActionWheelState extends State<IconActionWheel> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  ActionItem? _hoveredAction;
  
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
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const double wheelRadius = 75.0;
    const double buttonSize = 48.0;
    
    // Define the 4 actions with their icons and callbacks
    final actions = [
      ActionItem(
        icon: Icons.info_outline_rounded,
        label: 'Info',
        onTap: widget.onDetails,
        color: colorScheme.primary,
      ),
      ActionItem(
        icon: Icons.zoom_in_rounded,
        label: 'Zoom',
        onTap: widget.onZoom,
        color: colorScheme.primary,
      ),
      ActionItem(
        icon: Icons.open_with_rounded,
        label: 'Move',
        onTap: widget.onMove,
        color: colorScheme.primary,
      ),
      ActionItem(
        icon: Icons.delete_outline_rounded,
        label: 'Delete',
        onTap: widget.onDelete,
        color: colorScheme.error,
      ),
    ];
    
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
        // The action wheel
        Positioned(
          left: widget.position.dx - wheelRadius - buttonSize/2,
          top: widget.position.dy - wheelRadius - buttonSize/2,
          child: AnimatedBuilder(
            animation: _scaleAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _scaleAnimation.value,
                child: SizedBox(
                  width: (wheelRadius + buttonSize/2) * 2,
                  height: (wheelRadius + buttonSize/2) * 2,
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
                      // Center selected icon indicator
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colorScheme.primary.withOpacity(0.1),
                          border: Border.all(
                            color: colorScheme.primary.withOpacity(0.3),
                            width: 2,
                          ),
                        ),
                        child: Icon(
                          Icons.location_on_rounded,
                          color: colorScheme.primary,
                          size: 20,
                        ),
                      ),
                      // Action buttons arranged in circle
                      ...actions.asMap().entries.map((entry) {
                        final index = entry.key;
                        final action = entry.value;
                        // Position buttons at top, right, bottom, left
                        final angles = [
                          -math.pi / 2,  // Top
                          0,             // Right
                          math.pi / 2,   // Bottom
                          math.pi,       // Left
                        ];
                        final angle = angles[index];
                        
                        return Positioned(
                          left: wheelRadius + math.cos(angle) * wheelRadius - buttonSize/2 + buttonSize/2,
                          top: wheelRadius + math.sin(angle) * wheelRadius - buttonSize/2 + buttonSize/2,
                          child: _buildActionButton(
                            action: action,
                            colorScheme: colorScheme,
                            isDark: isDark,
                            buttonSize: buttonSize,
                            isHovered: _hoveredAction == action,
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
  
  Widget _buildActionButton({
    required ActionItem action,
    required ColorScheme colorScheme,
    required bool isDark,
    required double buttonSize,
    required bool isHovered,
  }) {
    return GestureDetector(
      onTapDown: (_) {
        setState(() {
          _hoveredAction = action;
        });
        // Immediate action on tap down
        action.onTap();
      },
      onTapUp: (_) {
        setState(() {
          _hoveredAction = null;
        });
      },
      onTapCancel: () {
        setState(() {
          _hoveredAction = null;
        });
      },
      child: Transform.scale(
        scale: isHovered ? 1.1 : 1.0,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 50),
          width: buttonSize,
          height: buttonSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isHovered 
              ? action.color
              : colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: isHovered 
                  ? action.color.withOpacity(0.4)
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
            action.icon,
            size: 22,
            color: isHovered 
              ? colorScheme.onPrimary
              : action.color,
          ),
        ),
      ),
    );
  }
}

class ActionItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  
  ActionItem({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.color,
  });
}