import 'package:flutter/material.dart';

import '../../styles/tokens.dart';

/// Status indicator at the bottom-right of an avatar.
enum GridAvatarStatus { none, live, paused, offline }

/// Deterministic gradient avatar with optional ring + status dot.
///
/// Matches the spec in the design handoff (`AVATAR_PALETTES`). Stable per
/// name so the same user always picks the same palette across screens.
class GridAvatar extends StatelessWidget {
  const GridAvatar({
    super.key,
    required this.name,
    this.size = 44,
    this.imageUrl,
    this.status = GridAvatarStatus.none,
    this.ring = false,
    this.padding = 0,
  });

  final String name;
  final double size;
  final String? imageUrl;
  final GridAvatarStatus status;

  /// Outer halo ring; mint when [status] is live, otherwise hairlineStrong.
  final bool ring;

  /// Extra bg padding around the avatar (used when overlapping cards).
  final double padding;

  static const _palettes = <List<Color>>[
    [Color(0xFF00DBA4), Color(0xFF0F7B5E)],
    [Color(0xFF6DD3F5), Color(0xFF1F6E8F)],
    [Color(0xFFB79EFF), Color(0xFF5B4690)],
    [Color(0xFFF5B947), Color(0xFF8A5E15)],
    [Color(0xFFFF8E72), Color(0xFF8A3F2A)],
    [Color(0xFF7DD181), Color(0xFF2F6B33)],
    [Color(0xFFE879C1), Color(0xFF7B2E60)],
    [Color(0xFF9DC3FF), Color(0xFF34619D)],
  ];

  static int _stableHash(String s) {
    var h = 5381;
    for (final code in s.codeUnits) {
      h = ((h << 5) + h + code) & 0x7fffffff;
    }
    return h;
  }

  String get _initial {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '·';
    final cleaned = trimmed.replaceFirst(RegExp(r'^@'), '');
    return cleaned.substring(0, 1).toUpperCase();
  }

  List<Color> get _palette =>
      _palettes[_stableHash(name) % _palettes.length];

  @override
  Widget build(BuildContext context) {
    final inner = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.4, -0.5),
          radius: 0.95,
          colors: _palette,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.white.withOpacity(0.18),
            offset: const Offset(0, 1),
            blurRadius: 0,
          ),
        ],
      ),
      alignment: Alignment.center,
      child: imageUrl != null
          ? ClipOval(
              child: Image.network(
                imageUrl!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _fallbackInitial(),
              ),
            )
          : _fallbackInitial(),
    );

    Widget body = inner;

    if (ring) {
      body = Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: GridTokens.bg,
          border: Border.all(
            width: 2,
            color: status == GridAvatarStatus.live
                ? GridTokens.mint
                : GridTokens.hairlineStrong,
          ),
        ),
        child: inner,
      );
    } else if (padding > 0) {
      body = Container(
        padding: EdgeInsets.all(padding),
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: GridTokens.bg,
        ),
        child: inner,
      );
    }

    if (status == GridAvatarStatus.none) return body;

    final dotColor = switch (status) {
      GridAvatarStatus.live => GridTokens.mint,
      GridAvatarStatus.paused => GridTokens.paused,
      GridAvatarStatus.offline => GridTokens.text3,
      _ => Colors.transparent,
    };
    final dotSize = (size * 0.28).clamp(8.0, 16.0);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        body,
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: dotSize,
            height: dotSize,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
              border: Border.all(color: GridTokens.bg, width: 2),
              boxShadow: status == GridAvatarStatus.live
                  ? [
                      BoxShadow(
                        color: GridTokens.mint.withOpacity(0.6),
                        blurRadius: 6,
                      ),
                    ]
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _fallbackInitial() => Text(
        _initial,
        style: TextStyle(
          fontFamily: 'Geist',
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: size * 0.40,
        ),
      );
}
