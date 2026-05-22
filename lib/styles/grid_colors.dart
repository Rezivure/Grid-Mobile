import 'package:flutter/material.dart';

@immutable
class GridColors extends ThemeExtension<GridColors> {
  const GridColors({
    required this.bg,
    required this.bgWarm,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.text,
    required this.text2,
    required this.text3,
    required this.text4,
    required this.hairline,
    required this.hairlineStrong,
    required this.mint,
    required this.mintDim,
    required this.mintSoft,
    required this.mintFaint,
    required this.amber,
    required this.amberSoft,
    required this.danger,
    required this.dangerSoft,
    required this.driving,
    required this.walking,
    required this.paused,
  });

  final Color bg;
  final Color bgWarm;
  final Color surface;
  final Color surface2;
  final Color surface3;
  final Color text;
  final Color text2;
  final Color text3;
  final Color text4;
  final Color hairline;
  final Color hairlineStrong;
  final Color mint;
  final Color mintDim;
  final Color mintSoft;
  final Color mintFaint;
  final Color amber;
  final Color amberSoft;
  final Color danger;
  final Color dangerSoft;
  final Color driving;
  final Color walking;
  final Color paused;

  factory GridColors.dark() => const GridColors(
        bg: Color(0xFF0B0D0F),
        bgWarm: Color(0xFF0D0F11),
        surface: Color(0xFF15181B),
        surface2: Color(0xFF1B1F23),
        surface3: Color(0xFF232A2F),
        text: Color(0xFFF4F5F7),
        text2: Color(0x9EF4F5F7),
        text3: Color(0x66F4F5F7),
        text4: Color(0x38F4F5F7),
        hairline: Color(0x12FFFFFF),
        hairlineStrong: Color(0x1FFFFFFF),
        mint: Color(0xFF00DBA4),
        mintDim: Color(0xFF00B589),
        mintSoft: Color(0x2900DBA4),
        mintFaint: Color(0x1400DBA4),
        amber: Color(0xFFF5B947),
        amberSoft: Color(0x2DF5B947),
        danger: Color(0xFFFF6058),
        dangerSoft: Color(0x29FF6058),
        driving: Color(0xFF6DD3F5),
        walking: Color(0xFF7DD181),
        paused: Color(0xFFB79EFF),
      );

  factory GridColors.light() => const GridColors(
        bg: Color(0xFFF7F8F9),
        bgWarm: Color(0xFFF9F8F6),
        surface: Color(0xFFFFFFFF),
        surface2: Color(0xFFF0F1F3),
        surface3: Color(0xFFE5E7EA),
        text: Color(0xFF0B0D0F),
        text2: Color(0xFF3A3F45),
        text3: Color(0xFF6E747C),
        text4: Color(0xFFA4A9B0),
        hairline: Color(0xFFE1E3E7),
        hairlineStrong: Color(0xFFD1D5DB),
        mint: Color(0xFF00DBA4),
        mintDim: Color(0xFF00B589),
        mintSoft: Color(0x2900DBA4),
        mintFaint: Color(0xFFE8F8F2),
        amber: Color(0xFFF5B947),
        amberSoft: Color(0xFFFDF1DA),
        danger: Color(0xFFFF6058),
        dangerSoft: Color(0xFFFDE7E5),
        driving: Color(0xFF6DD3F5),
        walking: Color(0xFF7DD181),
        paused: Color(0xFFB79EFF),
      );

  @override
  GridColors copyWith({
    Color? bg,
    Color? bgWarm,
    Color? surface,
    Color? surface2,
    Color? surface3,
    Color? text,
    Color? text2,
    Color? text3,
    Color? text4,
    Color? hairline,
    Color? hairlineStrong,
    Color? mint,
    Color? mintDim,
    Color? mintSoft,
    Color? mintFaint,
    Color? amber,
    Color? amberSoft,
    Color? danger,
    Color? dangerSoft,
    Color? driving,
    Color? walking,
    Color? paused,
  }) {
    return GridColors(
      bg: bg ?? this.bg,
      bgWarm: bgWarm ?? this.bgWarm,
      surface: surface ?? this.surface,
      surface2: surface2 ?? this.surface2,
      surface3: surface3 ?? this.surface3,
      text: text ?? this.text,
      text2: text2 ?? this.text2,
      text3: text3 ?? this.text3,
      text4: text4 ?? this.text4,
      hairline: hairline ?? this.hairline,
      hairlineStrong: hairlineStrong ?? this.hairlineStrong,
      mint: mint ?? this.mint,
      mintDim: mintDim ?? this.mintDim,
      mintSoft: mintSoft ?? this.mintSoft,
      mintFaint: mintFaint ?? this.mintFaint,
      amber: amber ?? this.amber,
      amberSoft: amberSoft ?? this.amberSoft,
      danger: danger ?? this.danger,
      dangerSoft: dangerSoft ?? this.dangerSoft,
      driving: driving ?? this.driving,
      walking: walking ?? this.walking,
      paused: paused ?? this.paused,
    );
  }

  @override
  GridColors lerp(ThemeExtension<GridColors>? other, double t) {
    if (other is! GridColors) return this;
    return GridColors(
      bg: Color.lerp(bg, other.bg, t)!,
      bgWarm: Color.lerp(bgWarm, other.bgWarm, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      surface3: Color.lerp(surface3, other.surface3, t)!,
      text: Color.lerp(text, other.text, t)!,
      text2: Color.lerp(text2, other.text2, t)!,
      text3: Color.lerp(text3, other.text3, t)!,
      text4: Color.lerp(text4, other.text4, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      hairlineStrong: Color.lerp(hairlineStrong, other.hairlineStrong, t)!,
      mint: Color.lerp(mint, other.mint, t)!,
      mintDim: Color.lerp(mintDim, other.mintDim, t)!,
      mintSoft: Color.lerp(mintSoft, other.mintSoft, t)!,
      mintFaint: Color.lerp(mintFaint, other.mintFaint, t)!,
      amber: Color.lerp(amber, other.amber, t)!,
      amberSoft: Color.lerp(amberSoft, other.amberSoft, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerSoft: Color.lerp(dangerSoft, other.dangerSoft, t)!,
      driving: Color.lerp(driving, other.driving, t)!,
      walking: Color.lerp(walking, other.walking, t)!,
      paused: Color.lerp(paused, other.paused, t)!,
    );
  }
}

extension GridColorsContext on BuildContext {
  GridColors get gridColors => Theme.of(this).extension<GridColors>()!;
}
