import 'dart:io' show Platform;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:grid_frontend/models/map_icon.dart';
import 'package:grid_frontend/services/in_app_notifier.dart';
import 'package:grid_frontend/styles/tokens.dart';
import 'package:grid_frontend/styles/grid_colors.dart';
import 'package:grid_frontend/widgets/grid/grid_button.dart';
import 'package:grid_frontend/widgets/grid/grid_mono.dart';

/// Floating glass card shown when "Details" is tapped from the icon action
/// wheel. Matches the user info bubble pattern (spec §5.25): identity row,
/// mono coordinate caption, mini-action row at the bottom, glass-y look.
///
/// All existing callbacks (onClose, onUpdate, onDelete, onEditingChanged)
/// are preserved so MapTab's wiring keeps working without changes.
class MapIconInfoBubble extends StatefulWidget {
  final MapIcon icon;
  final String? creatorName;
  final LatLng position;
  final VoidCallback onClose;
  final VoidCallback? onDelete;
  final Function(String name, String? description)? onUpdate;
  final Function(bool)? onEditingChanged;

  const MapIconInfoBubble({
    Key? key,
    required this.icon,
    required this.position,
    required this.onClose,
    this.creatorName,
    this.onDelete,
    this.onUpdate,
    this.onEditingChanged,
  }) : super(key: key);

  @override
  State<MapIconInfoBubble> createState() => _MapIconInfoBubbleState();
}

class _MapIconInfoBubbleState extends State<MapIconInfoBubble> {
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  bool _isEditingName = false;
  bool _isEditingDescription = false;

  @override
  void initState() {
    super.initState();
    final fallback = widget.icon.iconData.isEmpty
        ? 'Pin'
        : '${widget.icon.iconData.substring(0, 1).toUpperCase()}${widget.icon.iconData.substring(1)}';
    _nameController = TextEditingController(text: widget.icon.name ?? fallback);
    _descriptionController =
        TextEditingController(text: widget.icon.description ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _saveName() {
    if (_nameController.text.isNotEmpty && widget.onUpdate != null) {
      widget.onUpdate!(_nameController.text, widget.icon.description);
    }
    setState(() => _isEditingName = false);
  }

  void _saveDescription() {
    if (widget.onUpdate != null) {
      widget.onUpdate!(
        _nameController.text,
        _descriptionController.text.isEmpty
            ? null
            : _descriptionController.text,
      );
    }
    setState(() {
      _isEditingDescription = false;
      widget.onEditingChanged?.call(false);
    });
  }

  Future<void> _handleDelete() async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.9,
            ),
            decoration: BoxDecoration(
              color: context.gridColors.surface,
              borderRadius: BorderRadius.circular(GridTokens.rXl),
              border: Border.all(color: context.gridColors.hairlineStrong),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: context.gridColors.dangerSoft,
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
                          color: context.gridColors.danger.withOpacity(0.18),
                          borderRadius:
                              BorderRadius.circular(GridTokens.rMd),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.delete_outline_rounded,
                          color: context.gridColors.danger,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Delete icon',
                              style: GoogleFonts.getFont(
                                'Geist',
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.015,
                                color: context.gridColors.text,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "This can't be undone.",
                              style: GoogleFonts.getFont(
                                'Geist',
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                                color: context.gridColors.text2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                  child: Text(
                    'This icon will be permanently removed from the map.',
                    style: GoogleFonts.getFont(
                      'Geist',
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: context.gridColors.text2,
                      height: 1.45,
                    ),
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
                          onPressed: () => Navigator.of(context).pop(false),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GridButton(
                          label: 'Delete',
                          style: GridButtonStyle.danger,
                          onPressed: () => Navigator.of(context).pop(true),
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

    if (shouldDelete == true && widget.onDelete != null) {
      widget.onDelete!();
      widget.onClose();
    }
  }

  void _copyCoordinates(BuildContext context, LatLng position) {
    final coordinates =
        '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
    Clipboard.setData(ClipboardData(text: coordinates));

    InAppNotifier.instance.show(
      title: 'Coordinates copied',
      variant: InAppNotificationVariant.success,
      duration: const Duration(seconds: 2),
    );
  }

  String _formatCoordinates(LatLng p) {
    final lat = p.latitude;
    final lng = p.longitude;
    final latStr = '${lat.abs().toStringAsFixed(4)}° ${lat >= 0 ? 'N' : 'S'}';
    final lngStr = '${lng.abs().toStringAsFixed(4)}° ${lng >= 0 ? 'E' : 'W'}';
    return '$latStr  $lngStr';
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final dateFormat = DateFormat('MMM d, h:mm a');

    return Positioned(
      top: 100,
      left: (screenWidth - 280) / 2,
      width: 280,
      child: Material(
        color: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(GridTokens.rLg),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                color: context.gridColors.surface.withOpacity(0.95),
                borderRadius: BorderRadius.circular(GridTokens.rLg),
                border: Border.all(
                  color: context.gridColors.hairlineStrong,
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
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _IdentityRow(
                      iconData: _getIconData(widget.icon.iconData),
                      coordinatesLabel: _formatCoordinates(widget.position),
                      onCopyCoordinates: () =>
                          _copyCoordinates(context, widget.position),
                      onClose: widget.onClose,
                      nameController: _nameController,
                      isEditingName: _isEditingName,
                      canEdit: widget.onUpdate != null,
                      onStartEditName: () => setState(() {
                        _isEditingName = true;
                      }),
                      onSaveName: _saveName,
                    ),
                    const SizedBox(height: 10),
                    _MetaRow(
                      creatorName: widget.creatorName,
                      createdAt: dateFormat.format(widget.icon.createdAt),
                    ),
                    const SizedBox(height: 10),
                    _DescriptionCard(
                      controller: _descriptionController,
                      isEditing: _isEditingDescription,
                      canEdit: widget.onUpdate != null,
                      onStartEdit: () {
                        setState(() {
                          _isEditingDescription = true;
                          widget.onEditingChanged?.call(true);
                        });
                      },
                      onSave: _saveDescription,
                    ),
                    const SizedBox(height: 12),
                    _ActionRow(
                      onOpenInMaps: () => _openInMaps(
                          widget.icon.latitude, widget.icon.longitude),
                      onCopy: () => _copyCoordinates(context, widget.position),
                      onDelete:
                          widget.onDelete != null ? _handleDelete : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  IconData _getIconData(String iconType) {
    switch (iconType) {
      case 'pin':
        return Icons.location_on_rounded;
      case 'warning':
        return Icons.warning_rounded;
      case 'food':
        return Icons.restaurant_rounded;
      case 'car':
        return Icons.directions_car_rounded;
      case 'home':
        return Icons.home_rounded;
      case 'star':
        return Icons.star_rounded;
      case 'heart':
        return Icons.favorite_rounded;
      case 'flag':
        return Icons.flag_rounded;
      default:
        return Icons.place_rounded;
    }
  }

  Future<void> _openInMaps(double lat, double lng) async {
    try {
      String? mapChoice;

      if (Platform.isIOS) {
        mapChoice = await showDialog<String>(
          context: context,
          builder: (BuildContext context) {
            return Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 260),
                decoration: BoxDecoration(
                  color: context.gridColors.surface,
                  borderRadius: BorderRadius.circular(GridTokens.rXl),
                  border: Border.all(color: context.gridColors.hairlineStrong),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Open in',
                        style: GoogleFonts.getFont(
                          'Geist',
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: context.gridColors.text,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _MapChoiceTile(
                        label: 'Apple Maps',
                        iconColor: context.gridColors.driving,
                        onTap: () => Navigator.of(context).pop('apple'),
                      ),
                      const SizedBox(height: 10),
                      _MapChoiceTile(
                        label: 'Google Maps',
                        iconColor: context.gridColors.walking,
                        onTap: () => Navigator.of(context).pop('google'),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                        ),
                        child: Text(
                          'Cancel',
                          style: GoogleFonts.getFont(
                            'Geist',
                            color: context.gridColors.text3,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );

        if (mapChoice == null) return;
      } else {
        mapChoice = 'google';
      }

      if (mapChoice == 'apple') {
        final appleMapsUrl = Uri.parse('maps://?q=$lat,$lng');
        if (await canLaunchUrl(appleMapsUrl)) {
          await launchUrl(appleMapsUrl);
        } else {
          final webAppleMapsUrl =
              Uri.parse('https://maps.apple.com/?q=$lat,$lng');
          await launchUrl(webAppleMapsUrl,
              mode: LaunchMode.externalApplication);
        }
      } else {
        if (Platform.isIOS) {
          final googleMapsAppUrl = Uri.parse('comgooglemaps://?q=$lat,$lng');
          if (await canLaunchUrl(googleMapsAppUrl)) {
            await launchUrl(googleMapsAppUrl);
          } else {
            final googleMapsWebUrl = Uri.parse(
                'https://www.google.com/maps/search/?api=1&query=$lat,$lng');
            await launchUrl(googleMapsWebUrl,
                mode: LaunchMode.externalApplication);
          }
        } else {
          final googleMapsUrl = Uri.parse('geo:$lat,$lng?q=$lat,$lng');
          if (await canLaunchUrl(googleMapsUrl)) {
            await launchUrl(googleMapsUrl);
          } else {
            final googleMapsWebUrl = Uri.parse(
                'https://www.google.com/maps/search/?api=1&query=$lat,$lng');
            await launchUrl(googleMapsWebUrl,
                mode: LaunchMode.externalApplication);
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        InAppNotifier.instance.show(
          title: 'Could not open maps application',
          variant: InAppNotificationVariant.error,
          duration: const Duration(seconds: 2),
        );
      }
    }
  }
}

class _IdentityRow extends StatelessWidget {
  const _IdentityRow({
    required this.iconData,
    required this.coordinatesLabel,
    required this.onCopyCoordinates,
    required this.onClose,
    required this.nameController,
    required this.isEditingName,
    required this.canEdit,
    required this.onStartEditName,
    required this.onSaveName,
  });

  final IconData iconData;
  final String coordinatesLabel;
  final VoidCallback onCopyCoordinates;
  final VoidCallback onClose;
  final TextEditingController nameController;
  final bool isEditingName;
  final bool canEdit;
  final VoidCallback onStartEditName;
  final VoidCallback onSaveName;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Mint-faint icon tile in place of the avatar.
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: context.gridColors.mintFaint,
            borderRadius: BorderRadius.circular(GridTokens.rMd),
            border: Border.all(color: context.gridColors.hairlineStrong, width: 1),
          ),
          alignment: Alignment.center,
          child: Icon(iconData, size: 22, color: context.gridColors.mint),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: isEditingName
                        ? TextField(
                            controller: nameController,
                            autofocus: true,
                            style: GoogleFonts.getFont(
                              'Geist',
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.01,
                              color: context.gridColors.text,
                            ),
                            decoration: const InputDecoration(
                              isDense: true,
                              border: UnderlineInputBorder(),
                              contentPadding: EdgeInsets.zero,
                            ),
                            onSubmitted: (_) => onSaveName(),
                          )
                        : Text(
                            nameController.text,
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
                  const SizedBox(width: 6),
                  if (canEdit && !isEditingName)
                    InkWell(
                      onTap: onStartEditName,
                      borderRadius: BorderRadius.circular(GridTokens.rSm),
                      child: Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.edit_rounded,
                          size: 14,
                          color: context.gridColors.text3,
                        ),
                      ),
                    ),
                  if (isEditingName)
                    InkWell(
                      onTap: onSaveName,
                      borderRadius: BorderRadius.circular(GridTokens.rSm),
                      child: Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: context.gridColors.mint,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              InkWell(
                onTap: onCopyCoordinates,
                borderRadius: BorderRadius.circular(GridTokens.rSm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: GridMono(
                    coordinatesLabel,
                    size: 10.5,
                    uppercase: false,
                    color: context.gridColors.text3,
                    letterSpacing: 0.04,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        _CloseButton(onTap: onClose),
      ],
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: context.gridColors.surface2,
            shape: BoxShape.circle,
            border: Border.all(color: context.gridColors.hairline, width: 1),
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.close_rounded,
            size: 16,
            color: context.gridColors.text2,
          ),
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.creatorName, required this.createdAt});

  final String? creatorName;
  final String createdAt;

  @override
  Widget build(BuildContext context) {
    final parts = <Widget>[];
    if (creatorName != null) {
      parts.add(_MonoChip(
        icon: Icons.person_outline_rounded,
        text: 'BY ${creatorName!.toUpperCase()}',
      ));
    }
    parts.add(_MonoChip(
      icon: Icons.access_time_rounded,
      text: createdAt.toUpperCase(),
    ));
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: parts,
    );
  }
}

class _MonoChip extends StatelessWidget {
  const _MonoChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: context.gridColors.surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: context.gridColors.hairline, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: context.gridColors.text3),
          const SizedBox(width: 4),
          GridMono(
            text,
            size: 10,
            uppercase: false,
            color: context.gridColors.text2,
            letterSpacing: 0.06,
          ),
        ],
      ),
    );
  }
}

class _DescriptionCard extends StatelessWidget {
  const _DescriptionCard({
    required this.controller,
    required this.isEditing,
    required this.canEdit,
    required this.onStartEdit,
    required this.onSave,
  });

  final TextEditingController controller;
  final bool isEditing;
  final bool canEdit;
  final VoidCallback onStartEdit;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 10),
      decoration: BoxDecoration(
        color: context.gridColors.surface2,
        borderRadius: BorderRadius.circular(GridTokens.rMd),
        border: Border.all(
          color: isEditing ? context.gridColors.mint : context.gridColors.hairline,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.notes_rounded,
                size: 12,
                color: context.gridColors.text3,
              ),
              const SizedBox(width: 6),
              GridMono(
                'DESCRIPTION',
                size: 10,
                color: context.gridColors.text3,
                letterSpacing: 0.08,
              ),
              const Spacer(),
              if (canEdit && !isEditing)
                InkWell(
                  onTap: onStartEdit,
                  borderRadius: BorderRadius.circular(GridTokens.rSm),
                  child: Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.edit_rounded,
                      size: 14,
                      color: context.gridColors.text3,
                    ),
                  ),
                ),
              if (isEditing)
                InkWell(
                  onTap: onSave,
                  borderRadius: BorderRadius.circular(GridTokens.rSm),
                  child: Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.check_rounded,
                      size: 16,
                      color: context.gridColors.mint,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (isEditing)
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 8,
              minLines: 4,
              style: GoogleFonts.getFont(
                'Geist',
                fontSize: 13,
                color: context.gridColors.text,
                height: 1.45,
              ),
              textInputAction: TextInputAction.newline,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 8),
                hintText: 'Add a description…',
                hintStyle: GoogleFonts.getFont(
                  'Geist',
                  fontSize: 13,
                  color: context.gridColors.text3,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(GridTokens.rSm),
                  borderSide: BorderSide(color: context.gridColors.hairline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(GridTokens.rSm),
                  borderSide: BorderSide(color: context.gridColors.mint),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(GridTokens.rSm),
                  borderSide: BorderSide(color: context.gridColors.hairline),
                ),
              ),
            )
          else
            Text(
              controller.text.isEmpty
                  ? (canEdit
                      ? 'Tap to add a description…'
                      : 'No description')
                  : controller.text,
              style: GoogleFonts.getFont(
                'Geist',
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: controller.text.isEmpty
                    ? context.gridColors.text3
                    : context.gridColors.text,
                height: 1.45,
                fontStyle: controller.text.isEmpty
                    ? FontStyle.italic
                    : FontStyle.normal,
              ),
            ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.onOpenInMaps,
    required this.onCopy,
    required this.onDelete,
  });

  final VoidCallback onOpenInMaps;
  final VoidCallback onCopy;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _MiniBtn(
            icon: Icons.near_me_rounded,
            label: 'Route',
            onTap: onOpenInMaps,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _MiniBtn(
            icon: Icons.copy_rounded,
            label: 'Copy',
            onTap: onCopy,
          ),
        ),
        if (onDelete != null) ...[
          const SizedBox(width: 6),
          Expanded(
            child: _MiniBtn(
              icon: Icons.delete_outline_rounded,
              label: 'Delete',
              destructive: true,
              onTap: onDelete!,
            ),
          ),
        ],
      ],
    );
  }
}

class _MiniBtn extends StatelessWidget {
  const _MiniBtn({
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
  Widget build(BuildContext context) {
    final fg = destructive ? context.gridColors.danger : context.gridColors.text;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(GridTokens.rMd),
        child: Ink(
          height: 38,
          decoration: BoxDecoration(
            color: context.gridColors.surface2,
            borderRadius: BorderRadius.circular(GridTokens.rMd),
            border: Border.all(color: context.gridColors.hairline, width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 5),
              Text(
                label,
                style: GoogleFonts.getFont(
                  'Geist',
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.005,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapChoiceTile extends StatelessWidget {
  const _MapChoiceTile({
    required this.label,
    required this.iconColor,
    required this.onTap,
  });

  final String label;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: context.gridColors.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.gridColors.hairline),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.map_outlined, color: iconColor, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.getFont(
                'Geist',
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: context.gridColors.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
