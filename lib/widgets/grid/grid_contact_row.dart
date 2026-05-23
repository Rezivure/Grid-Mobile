import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../styles/grid_colors.dart';
import 'grid_avatar.dart';
import 'grid_mono.dart';
import 'grid_status_pill.dart';
import 'sharing_row_state.dart';

/// 52pt min-height contact row — used in the bottom sheet's contacts list
/// and the standalone contacts list.
class GridContactRow extends StatelessWidget {
  const GridContactRow({
    super.key,
    required this.name,
    required this.handle,
    this.placeLine,
    this.timeText,
    this.distanceText,
    this.statusKind,
    this.statusLabel,
    this.avatarStatus = GridAvatarStatus.idle,
    this.imageUrl,
    this.userId,
    this.highlighted = false,
    this.onTap,
    this.showDivider = true,
    this.sharingState = SharingRowState.active,
  });

  final String name;
  final String handle;
  final String? placeLine;
  final String? timeText;
  final String? distanceText;
  final GridStatusKind? statusKind;
  final String? statusLabel;
  final GridAvatarStatus avatarStatus;
  final String? imageUrl;
  final String? userId;
  final bool highlighted;
  final VoidCallback? onTap;
  final bool showDivider;
  final SharingRowState sharingState;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: highlighted ? context.gridColors.mintFaint : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            border: showDivider
                ? Border(
                    bottom:
                        BorderSide(color: context.gridColors.hairline, width: 1),
                  )
                : null,
          ),
          child: Opacity(
            opacity: sharingState == SharingRowState.active ? 1.0 : 0.55,
            child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              GridAvatar(
                name: name,
                size: 44,
                status: avatarStatus,
                imageUrl: imageUrl,
                userId: userId,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.getFont(
                              'Geist',
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.01,
                              color: context.gridColors.text,
                            ),
                          ),
                        ),
                        if (sharingState == SharingRowState.scheduledOut) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.schedule_rounded,
                            size: 12,
                            color: context.gridColors.text3,
                          ),
                        ],
                        if (sharingState == SharingRowState.off) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.visibility_off_rounded,
                            size: 12,
                            color: context.gridColors.text3,
                          ),
                        ],
                        if (avatarStatus == GridAvatarStatus.live) ...[
                          const SizedBox(width: 6),
                          const GridLiveBadge(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (placeLine != null)
                          Flexible(
                            child: Text(
                              placeLine!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.getFont(
                                'Geist',
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                                color: context.gridColors.text2,
                              ),
                            ),
                          ),
                        if (placeLine != null && timeText != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Text(
                              '·',
                              style: TextStyle(
                                color: context.gridColors.text3,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        if (timeText != null)
                          GridMono(
                            timeText!,
                            color: context.gridColors.text3,
                            size: 11,
                            letterSpacing: 0.02,
                            uppercase: false,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (distanceText != null)
                    GridMono(
                      distanceText!,
                      color: context.gridColors.text2,
                      size: 11,
                      letterSpacing: 0.02,
                      uppercase: false,
                    ),
                  if (statusKind != null && statusLabel != null) ...[
                    const SizedBox(height: 4),
                    GridStatusPill(
                      kind: statusKind!,
                      label: statusLabel!,
                    ),
                  ],
                ],
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }
}
