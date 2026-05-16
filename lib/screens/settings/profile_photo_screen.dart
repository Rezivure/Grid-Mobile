import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:grid_frontend/styles/tokens.dart';
import 'package:grid_frontend/widgets/grid/grid_avatar.dart';
import 'package:grid_frontend/widgets/grid/grid_button.dart';
import 'package:grid_frontend/widgets/grid/grid_segmented.dart';
import 'package:grid_frontend/widgets/user_avatar_bloc.dart';

/// Dedicated page for managing the local user's profile photo.
///
/// Replaces the in-method "Update Profile Photo" sheet that previously lived
/// inside `_pickAndUploadAvatar` in settings_page.dart. The actual
/// camera/gallery/upload + removal logic stays on the settings page —
/// this screen only invokes callbacks the parent supplies.
class ProfilePhotoScreen extends StatelessWidget {
  const ProfilePhotoScreen({
    super.key,
    required this.userId,
    required this.displayName,
    required this.onTakePhoto,
    required this.onChooseFromGallery,
    required this.onRemovePhoto,
  });

  final String userId;
  final String displayName;
  final Future<void> Function() onTakePhoto;
  final Future<void> Function() onChooseFromGallery;
  final Future<void> Function() onRemovePhoto;

  Future<void> _run(BuildContext context, Future<void> Function() action) async {
    Navigator.pop(context);
    await action();
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.9,
            ),
            decoration: BoxDecoration(
              color: GridTokens.surface,
              borderRadius: BorderRadius.circular(GridTokens.rXl),
              border: Border.all(color: GridTokens.hairline),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    color: GridTokens.dangerSoft,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(GridTokens.rXl),
                      topRight: Radius.circular(GridTokens.rXl),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: GridTokens.danger.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(GridTokens.rMd),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.delete_outline,
                          color: GridTokens.danger,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Remove photo',
                              style: GoogleFonts.getFont(
                                'Geist',
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: GridTokens.text,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Your contacts will see your initial instead.',
                              style: GoogleFonts.getFont(
                                'Geist',
                                fontSize: 13,
                                color: GridTokens.text2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: GridButton(
                          label: 'Cancel',
                          style: GridButtonStyle.secondary,
                          onPressed: () => Navigator.pop(context, false),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GridButton(
                          label: 'Remove',
                          style: GridButtonStyle.danger,
                          onPressed: () => Navigator.pop(context, true),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmed != true) return;
    if (!context.mounted) return;
    await _run(context, onRemovePhoto);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GridTokens.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Text(
          'Profile photo',
          style: GoogleFonts.getFont(
            'Geist',
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: GridTokens.text,
            letterSpacing: -0.01,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: GridTokens.text),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _buildInfoCard(),
            const SizedBox(height: 24),
            _buildAvatar(),
            const GridSectionHeader(text: 'PROFILE PHOTO'),
            Container(
              decoration: BoxDecoration(
                color: GridTokens.surface,
                borderRadius: BorderRadius.circular(GridTokens.rLg),
                border: Border.all(color: GridTokens.hairline),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  _ActionRow(
                    icon: Icons.camera_alt_outlined,
                    label: 'Take a photo',
                    subtitle: 'Use your camera',
                    onTap: () => _run(context, onTakePhoto),
                  ),
                  const Divider(
                    height: 1,
                    thickness: 1,
                    color: GridTokens.hairline,
                    indent: 56,
                  ),
                  _ActionRow(
                    icon: Icons.photo_library_outlined,
                    label: 'Choose from gallery',
                    subtitle: 'Select an existing photo',
                    onTap: () => _run(context, onChooseFromGallery),
                  ),
                  const Divider(
                    height: 1,
                    thickness: 1,
                    color: GridTokens.hairline,
                    indent: 56,
                  ),
                  _ActionRow(
                    icon: Icons.delete_outline_rounded,
                    label: 'Remove photo',
                    subtitle: 'Revert to your initial',
                    danger: true,
                    onTap: () => _confirmRemove(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: GridTokens.mintFaint,
        borderRadius: BorderRadius.circular(GridTokens.rLg),
        border: Border.all(color: GridTokens.mintSoft),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.lock_outline_rounded,
            color: GridTokens.mint,
            size: 18,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Your photo is end-to-end encrypted before it leaves the device.',
              style: GoogleFonts.getFont(
                'Geist',
                fontSize: 13,
                color: GridTokens.text2,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    const avatarSize = 132.0;
    return Center(
      child: SizedBox(
        width: avatarSize + 12,
        height: avatarSize + 12,
        child: Stack(
          alignment: Alignment.center,
          children: [
            GridAvatar(
              name: displayName.isEmpty ? 'Grid' : displayName,
              size: avatarSize,
              ring: true,
            ),
            if (userId.isNotEmpty)
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: ClipOval(
                    child: UserAvatarBloc(
                      userId: userId,
                      size: avatarSize - 4,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final fg = danger ? GridTokens.danger : GridTokens.text;
    final tileBg = danger ? GridTokens.dangerSoft : GridTokens.mintFaint;
    final iconColor = danger ? GridTokens.danger : GridTokens.mint;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: tileBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 16, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.getFont(
                        'Geist',
                        color: fg,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.01,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.getFont(
                        'Geist',
                        color: GridTokens.text3,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: GridTokens.text3,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
