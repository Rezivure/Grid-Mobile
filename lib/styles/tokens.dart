// Grid · Design tokens, Flutter
// Drop in to lib/styles/tokens.dart and replace the existing ColorScheme in main.dart.

import 'package:flutter/material.dart';

class GridTokens {
  // ── Brand ──────────────────────────────────────────────
  static const mint        = Color(0xFF00DBA4);
  static const mintDim     = Color(0xFF00B589);
  static const mintSoft    = Color(0x2900DBA4); // 16% alpha
  static const mintFaint   = Color(0x1400DBA4); //  8% alpha

  // Warmth accent — used sparingly (invite/trip moments only)
  static const amber       = Color(0xFFF5B947);
  static const amberSoft   = Color(0x2DF5B947); // 18% alpha

  // Status colors
  static const driving     = Color(0xFF6DD3F5);
  static const walking     = Color(0xFF7DD181);
  static const paused      = Color(0xFFB79EFF);
  static const danger      = Color(0xFFFF6058);
  static const dangerSoft  = Color(0x29FF6058);

  // ── Dark surfaces ──────────────────────────────────────
  static const bg          = Color(0xFF0B0D0F);
  static const bgWarm      = Color(0xFF0D0F11);
  static const surface     = Color(0xFF15181B);
  static const surface2    = Color(0xFF1B1F23);
  static const surface3    = Color(0xFF232A2F);

  static const hairline        = Color(0x12FFFFFF); //  7%
  static const hairlineStrong  = Color(0x1FFFFFFF); // 12%

  // ── Text ───────────────────────────────────────────────
  static const text   = Color(0xFFF4F5F7);
  static const text2  = Color(0x9EF4F5F7); // 62%
  static const text3  = Color(0x66F4F5F7); // 40%
  static const text4  = Color(0x38F4F5F7); // 22%

  // ── Map (used by your protomaps theme) ─────────────────
  static const mapBg     = Color(0xFF1A1F23);
  static const mapLand   = Color(0xFF20262B);
  static const mapWater  = Color(0xFF131A20);
  static const mapRoad   = Color(0xFF2D353B);
  static const mapRoad2  = Color(0xFF3A464D);
  static const mapLabel  = Color(0x61F4F5F7);

  // ── Type ───────────────────────────────────────────────
  // Load via google_fonts package: GoogleFonts.geist() / GoogleFonts.geistMono()
  static const fontUi   = 'Geist';
  static const fontMono = 'GeistMono';

  // ── Radii ──────────────────────────────────────────────
  static const rSm   = 8.0;
  static const rMd   = 12.0;
  static const rLg   = 16.0;
  static const rXl   = 22.0;
  static const r2Xl  = 28.0;

  // ── Hit targets ────────────────────────────────────────
  static const minTap = 44.0;

  // ── ColorScheme builder ────────────────────────────────
  static ColorScheme darkScheme() => const ColorScheme(
        brightness: Brightness.dark,
        primary: mint,
        onPrimary: Color(0xFF04201A),
        secondary: amber,
        onSecondary: Color(0xFF1A1106),
        tertiary: paused,
        onTertiary: bg,
        error: danger,
        onError: Color(0xFFFFFFFF),
        background: bg,
        onBackground: text,
        surface: surface,
        onSurface: text,
        surfaceVariant: surface2,
        onSurfaceVariant: text2,
        outline: hairlineStrong,
        outlineVariant: hairline,
        shadow: Color(0xCC000000),
      );

  // Optional light scheme (designs are dark-primary; this is a safety net)
  static ColorScheme lightScheme() => const ColorScheme(
        brightness: Brightness.light,
        primary: Color(0xFF0F9C76),
        onPrimary: Colors.white,
        secondary: Color(0xFFB4881F),
        onSecondary: Colors.white,
        tertiary: Color(0xFF5B4690),
        onTertiary: Colors.white,
        error: Color(0xFFCC362D),
        onError: Colors.white,
        background: Color(0xFFF7F8FA),
        onBackground: Color(0xFF0B0D0F),
        surface: Colors.white,
        onSurface: Color(0xFF0B0D0F),
        surfaceVariant: Color(0xFFEFF1F4),
        onSurfaceVariant: Color(0x99000000),
        outline: Color(0x1F000000),
        outlineVariant: Color(0x12000000),
        shadow: Color(0x29000000),
      );
}
