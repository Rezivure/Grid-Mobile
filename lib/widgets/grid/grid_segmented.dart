import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../styles/tokens.dart';
import 'grid_mono.dart';

class GridSegmentedTab {
  const GridSegmentedTab({
    required this.label,
    this.badgeCount = 0,
    this.badgeColor,
  });

  final String label;
  final int badgeCount;
  final Color? badgeColor;
}

/// Pill segmented control used for the People / Groups / Invites tabs at the
/// top of the map bottom sheet.
class GridSegmented extends StatelessWidget {
  const GridSegmented({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onChanged,
  });

  final List<GridSegmentedTab> tabs;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: GridTokens.surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: GridTokens.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < tabs.length; i++)
            _SegItem(
              tab: tabs[i],
              active: i == selected,
              onTap: () => onChanged(i),
            ),
        ],
      ),
    );
  }
}

class _SegItem extends StatelessWidget {
  const _SegItem({
    required this.tab,
    required this.active,
    required this.onTap,
  });

  final GridSegmentedTab tab;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: active ? GridTokens.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: active
                ? Border.all(color: GridTokens.hairlineStrong)
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tab.label,
                style: GoogleFonts.getFont(
                  'Geist',
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.01,
                  color: active ? GridTokens.text : GridTokens.text2,
                ),
              ),
              if (tab.badgeCount > 0) ...[
                const SizedBox(width: 6),
                GridMono(
                  '${tab.badgeCount}',
                  color: tab.badgeColor ?? GridTokens.text3,
                  size: 10,
                  letterSpacing: 0,
                  uppercase: false,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Mono-styled section header — used as separators in lists.
class GridSectionHeader extends StatelessWidget {
  const GridSectionHeader({
    super.key,
    required this.text,
    this.trailing,
  });

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
      child: Row(
        children: [
          Expanded(
            child: GridMono(
              text,
              color: GridTokens.text3,
              size: 10.5,
              letterSpacing: 0.12,
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
