import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:grid_frontend/styles/tokens.dart';
import 'package:grid_frontend/widgets/grid/grid_mono.dart';

/// Tap an existing map icon → iOS-style context menu (spec §5.26).
///
/// The targeted icon lifts (`Transform.scale(1.08)`) with a heavy shadow and
/// a small mono caption beneath it; a 200pt rounded-16 glass card with the
/// action rows floats to the right of the icon (or below if there's no
/// room). All existing callbacks (onDetails / onZoom / onMove / onDelete /
/// onCancel) are preserved.
///
/// MapTab passes the icon's screen-space position via [position]; the menu
/// uses that to anchor the lifted icon. An optional [iconType] and [label]
/// can be supplied to render the lifted preview accurately — if absent we
/// fall back to a generic pin / "PIN" caption so the call site doesn't
/// strictly have to change today.
class IconActionWheel extends StatefulWidget {
  final Offset position;
  final VoidCallback onDetails;
  final VoidCallback onDelete;
  final VoidCallback onZoom;
  final VoidCallback onMove;
  final VoidCallback onCancel;

  /// Optional callback so the user can share the icon with the group.
  /// MapTab may not pass this yet — we fall back to the existing details
  /// route when null so the row stays useful.
  final VoidCallback? onShare;

  /// Material icon name used for the lifted preview tile. Defaults to
  /// [Icons.location_on_rounded] when not provided.
  final IconData? iconData;

  /// Caption rendered under the lifted preview (e.g. "HOME"). Defaults to
  /// "PIN" when not provided.
  final String? label;

  const IconActionWheel({
    Key? key,
    required this.position,
    required this.onDetails,
    required this.onDelete,
    required this.onZoom,
    required this.onMove,
    required this.onCancel,
    this.onShare,
    this.iconData,
    this.label,
  }) : super(key: key);

  @override
  State<IconActionWheel> createState() => _IconActionWheelState();
}

class _IconActionWheelState extends State<IconActionWheel>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  static const double _menuWidth = 200;
  static const double _previewSize = 64;
  static const double _gap = 12;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 160),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0.96, end: 1.0).animate(
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
    final mediaSize = MediaQuery.of(context).size;
    final iconData = widget.iconData ?? Icons.location_on_rounded;
    final caption = (widget.label ?? 'pin').toUpperCase();

    final layout = _layout(mediaSize);

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
        // Lifted icon preview + caption.
        Positioned(
          left: layout.previewLeft,
          top: layout.previewTop,
          child: AnimatedBuilder(
            animation: _scaleAnimation,
            builder: (context, child) => Transform.scale(
              scale: _scaleAnimation.value * 1.08,
              child: child,
            ),
            child: _LiftedPreview(icon: iconData, caption: caption),
          ),
        ),
        // Floating menu card.
        Positioned(
          left: layout.menuLeft,
          top: layout.menuTop,
          child: AnimatedBuilder(
            animation: _scaleAnimation,
            builder: (context, child) => Opacity(
              opacity: _animationController.value,
              child: Transform.scale(
                alignment: layout.placeRight
                    ? Alignment.centerLeft
                    : Alignment.topCenter,
                scale: _scaleAnimation.value,
                child: child,
              ),
            ),
            child: _MenuCard(
              width: _menuWidth,
              onDetails: _wrap(widget.onDetails),
              onZoom: _wrap(widget.onZoom),
              onMove: _wrap(widget.onMove),
              onShare: _wrap(widget.onShare ?? widget.onDetails),
              onDelete: _wrap(widget.onDelete),
            ),
          ),
        ),
      ],
    );
  }

  // Wrap each callback so we don't fire-on-tap-down inadvertently — the
  // original wheel did fire on tap-down, but for an iOS-style menu the
  // expected behavior is tap-up. We still close on the parent's setState
  // path because the parent tears the menu down when it gets the callback.
  VoidCallback _wrap(VoidCallback cb) => cb;

  _MenuLayout _layout(Size mediaSize) {
    // Try placing the menu to the right of the icon.
    final iconCx = widget.position.dx;
    final iconCy = widget.position.dy;

    final previewLeft = iconCx - _previewSize / 2;
    final previewTop = iconCy - _previewSize / 2;

    // Menu width + a small horizontal gap.
    final rightEdgeIfRight = iconCx + _previewSize / 2 + _gap + _menuWidth;
    final placeRight = rightEdgeIfRight <= mediaSize.width - 12;

    // Estimate menu height — 5 rows + divider + padding ≈ 240.
    const menuHeight = 244.0;

    double menuLeft;
    double menuTop;

    if (placeRight) {
      menuLeft = iconCx + _previewSize / 2 + _gap;
      // Vertically align the menu's top edge a hair above the icon center.
      menuTop = iconCy - 28;
    } else {
      // Place below the icon, centered horizontally on it.
      menuLeft = iconCx - _menuWidth / 2;
      menuTop = iconCy + _previewSize / 2 + _gap + 20; // leave room for caption.
    }

    // Clamp so the menu stays on-screen.
    menuLeft = menuLeft.clamp(12.0, mediaSize.width - _menuWidth - 12.0);
    menuTop = menuTop.clamp(80.0, mediaSize.height - menuHeight - 24.0);

    return _MenuLayout(
      previewLeft: previewLeft,
      previewTop: previewTop,
      menuLeft: menuLeft,
      menuTop: menuTop,
      placeRight: placeRight,
    );
  }
}

class _MenuLayout {
  const _MenuLayout({
    required this.previewLeft,
    required this.previewTop,
    required this.menuLeft,
    required this.menuTop,
    required this.placeRight,
  });

  final double previewLeft;
  final double previewTop;
  final double menuLeft;
  final double menuTop;
  final bool placeRight;
}

class _LiftedPreview extends StatelessWidget {
  const _LiftedPreview({required this.icon, required this.caption});

  final IconData icon;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: GridTokens.mint,
            borderRadius: BorderRadius.circular(GridTokens.rLg),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.55),
                blurRadius: 26,
                offset: const Offset(0, 14),
              ),
              BoxShadow(
                color: GridTokens.mint.withOpacity(0.35),
                blurRadius: 18,
                spreadRadius: 0.5,
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 28,
            color: GridTokens.bg,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: GridTokens.surface2,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: GridTokens.hairline, width: 1),
          ),
          child: GridMono(
            caption,
            size: 9.5,
            color: GridTokens.text2,
            letterSpacing: 0.12,
          ),
        ),
      ],
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({
    required this.width,
    required this.onDetails,
    required this.onZoom,
    required this.onMove,
    required this.onShare,
    required this.onDelete,
  });

  final double width;
  final VoidCallback onDetails;
  final VoidCallback onZoom;
  final VoidCallback onMove;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(GridTokens.rLg),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            decoration: BoxDecoration(
              color: GridTokens.surface.withOpacity(0.96),
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MenuRow(
                  icon: Icons.notifications_none_rounded,
                  label: 'Details',
                  onTap: onDetails,
                ),
                _MenuRow(
                  icon: Icons.zoom_in_rounded,
                  label: 'Zoom to icon',
                  onTap: onZoom,
                ),
                _MenuRow(
                  icon: Icons.swap_horiz_rounded,
                  label: 'Move',
                  onTap: onMove,
                ),
                _MenuRow(
                  icon: Icons.ios_share_rounded,
                  label: 'Share with group',
                  onTap: onShare,
                ),
                const Divider(
                  height: 1,
                  thickness: 1,
                  color: GridTokens.hairline,
                ),
                _MenuRow(
                  icon: Icons.delete_outline_rounded,
                  label: 'Delete icon',
                  onTap: onDelete,
                  destructive: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuRow extends StatefulWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  State<_MenuRow> createState() => _MenuRowState();
}

class _MenuRowState extends State<_MenuRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final fg = widget.destructive ? GridTokens.danger : GridTokens.text;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        onHighlightChanged: (v) => setState(() => _hover = v),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          color: _hover ? GridTokens.surface2 : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                child: Icon(widget.icon, size: 18, color: fg),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.label,
                  style: GoogleFonts.getFont(
                    'Geist',
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.01,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
