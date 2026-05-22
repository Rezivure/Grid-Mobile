import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:grid_frontend/styles/tokens.dart';
import 'package:grid_frontend/styles/grid_colors.dart';
import 'package:grid_frontend/widgets/grid/grid_mono.dart';

/// Long-press-on-map → pick an icon type. Replaced the radial wheel with a
/// glass card centered over the dim/blur backdrop (spec §5.26-ish, derived
/// from the marker action menu treatment). The [position] argument is kept
/// for API compatibility with `MapTab` but is no longer used for layout —
/// the card is screen-centered. Tap-outside dismisses.
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

class _IconSelectionWheelState extends State<IconSelectionWheel>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  static const List<_IconSlot> _slots = [
    _IconSlot(IconType.pin, Icons.location_on_rounded),
    _IconSlot(IconType.home, Icons.home_rounded),
    _IconSlot(IconType.food, Icons.restaurant_rounded),
    _IconSlot(IconType.car, Icons.directions_car_rounded),
    _IconSlot(IconType.star, Icons.star_rounded),
    _IconSlot(IconType.heart, Icons.favorite_rounded),
    _IconSlot(IconType.warning, Icons.warning_rounded),
    _IconSlot(IconType.flag, Icons.flag_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 160),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0.94, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Dim + blur backdrop. Tap dismisses.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onCancel,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
              child: Container(color: Colors.black.withOpacity(0.45)),
            ),
          ),
        ),
        // Glass card.
        Center(
          child: AnimatedBuilder(
            animation: _scaleAnimation,
            builder: (context, child) => Opacity(
              opacity: _animationController.value,
              child: Transform.scale(
                scale: _scaleAnimation.value,
                child: child,
              ),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 304),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(GridTokens.rXl),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: Container(
                    decoration: BoxDecoration(
                      color: context.gridColors.surface.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(GridTokens.rXl),
                      border: Border.all(
                        color: context.gridColors.hairlineStrong,
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.6),
                          blurRadius: 36,
                          offset: const Offset(0, 16),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _IconGrid(slots: _slots, onTap: _onTap),
                          const SizedBox(height: 14),
                          GridMono(
                            'DROP A PIN HERE',
                            size: 10.5,
                            color: context.gridColors.text3,
                            letterSpacing: 0.12,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _onTap(IconType type) {
    widget.onIconSelected(type);
  }
}

/// 4×2 grid of icon tiles. Pulled into its own class so the parent stays
/// declarative.
class _IconGrid extends StatelessWidget {
  const _IconGrid({required this.slots, required this.onTap});

  final List<_IconSlot> slots;
  final ValueChanged<IconType> onTap;

  @override
  Widget build(BuildContext context) {
    // 4 per row, 2 rows.
    const cols = 4;
    final rows = <Widget>[];
    for (var r = 0; r < (slots.length / cols).ceil(); r++) {
      final row = <Widget>[];
      for (var c = 0; c < cols; c++) {
        final idx = r * cols + c;
        if (idx >= slots.length) {
          row.add(const SizedBox(width: 56, height: 56));
        } else {
          row.add(_IconTile(slot: slots[idx], onTap: () => onTap(slots[idx].type)));
        }
        if (c < cols - 1) row.add(const SizedBox(width: 10));
      }
      rows.add(Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: row,
      ));
      if (r < (slots.length / cols).ceil() - 1) {
        rows.add(const SizedBox(height: 10));
      }
    }
    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }
}

class _IconTile extends StatefulWidget {
  const _IconTile({required this.slot, required this.onTap});

  final _IconSlot slot;
  final VoidCallback onTap;

  @override
  State<_IconTile> createState() => _IconTileState();
}

class _IconTileState extends State<_IconTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: context.gridColors.mintFaint,
            borderRadius: BorderRadius.circular(GridTokens.rMd),
            border: Border.all(
              color: context.gridColors.hairlineStrong,
              width: 1,
            ),
          ),
          alignment: Alignment.center,
          child: Icon(
            widget.slot.icon,
            size: 24,
            color: context.gridColors.mint,
          ),
        ),
      ),
    );
  }
}

class _IconSlot {
  const _IconSlot(this.type, this.icon);

  final IconType type;
  final IconData icon;
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
