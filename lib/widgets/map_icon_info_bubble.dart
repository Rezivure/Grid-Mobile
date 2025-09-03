import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:grid_frontend/models/map_icon.dart';
import 'package:intl/intl.dart';
import 'dart:io' show Platform;

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
    _nameController = TextEditingController(text: widget.icon.name ?? '${widget.icon.iconData.substring(0, 1).toUpperCase()}${widget.icon.iconData.substring(1)}');
    _descriptionController = TextEditingController(text: widget.icon.description ?? '');
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
    setState(() {
      _isEditingName = false;
    });
  }
  
  void _saveDescription() {
    if (widget.onUpdate != null) {
      widget.onUpdate!(_nameController.text, _descriptionController.text.isEmpty ? null : _descriptionController.text);
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
        final colorScheme = Theme.of(context).colorScheme;
        
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 300),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.shadow.withOpacity(0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: colorScheme.error.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.delete_outline,
                      color: colorScheme.error,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Delete Icon?',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'This icon will be permanently removed from the map.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface.withOpacity(0.8),
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: colorScheme.onSurface,
                            side: BorderSide(color: colorScheme.outline.withOpacity(0.3)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colorScheme.error,
                            foregroundColor: colorScheme.onError,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: const Text('Delete'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
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
    final coordinates = '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
    Clipboard.setData(ClipboardData(text: coordinates));
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Coordinates copied to clipboard'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final dateFormat = DateFormat('MMM d, h:mm a');
    
    return Positioned(
      top: 100,
      left: screenWidth * 0.15,
      right: screenWidth * 0.15,
      child: Material(
        color: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 280),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withOpacity(0.15),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with icon and close button
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceVariant.withOpacity(0.3),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    // Icon container
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withOpacity(0.1),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: colorScheme.outline.withOpacity(0.2),
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        _getIconData(widget.icon.iconData),
                        color: colorScheme.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Icon info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: _isEditingName
                                  ? TextField(
                                      controller: _nameController,
                                      autofocus: true,
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: colorScheme.onSurface,
                                      ),
                                      decoration: InputDecoration(
                                        isDense: true,
                                        border: UnderlineInputBorder(),
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                      onSubmitted: (_) => _saveName(),
                                    )
                                  : Text(
                                      _nameController.text,
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: colorScheme.onSurface,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                              ),
                              const SizedBox(width: 6),
                              if (widget.onUpdate != null && !_isEditingName)
                                InkWell(
                                  onTap: () {
                                    setState(() {
                                      _isEditingName = true;
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(6),
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: Icon(
                                      Icons.edit,
                                      size: 18,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                ),
                              if (_isEditingName)
                                InkWell(
                                  onTap: _saveName,
                                  borderRadius: BorderRadius.circular(6),
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: Icon(
                                      Icons.check,
                                      size: 18,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Close button
                    IconButton(
                      onPressed: widget.onClose,
                      icon: Icon(
                        Icons.close,
                        size: 20,
                        color: colorScheme.onSurface.withOpacity(0.5),
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    ),
                  ],
                ),
              ),
              
              // Body content - hide meta info when editing description for more space
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Meta info - only show when not editing description
                    if (!_isEditingDescription) ...[
                      if (widget.creatorName != null) ...[
                        Row(
                          children: [
                            Icon(
                              Icons.person_outline,
                              size: 14,
                            color: colorScheme.onSurface.withOpacity(0.5),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Placed by ${widget.creatorName}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurface.withOpacity(0.7),
                            ),
                          ),
                        ],
                        ),
                        const SizedBox(height: 6),
                      ],
                      
                      Row(
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 14,
                            color: colorScheme.onSurface.withOpacity(0.5),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            dateFormat.format(widget.icon.createdAt),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurface.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 6),
                      
                      Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 14,
                            color: colorScheme.onSurface.withOpacity(0.5),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${widget.position.latitude.toStringAsFixed(6)}, ${widget.position.longitude.toStringAsFixed(6)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurface.withOpacity(0.7),
                                fontFamily: 'monospace',
                                fontSize: 11,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // Copy button
                          InkWell(
                            onTap: () => _copyCoordinates(context, widget.position),
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(
                                Icons.copy,
                                size: 14,
                                color: colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 12),
                    ],
                    
                    // Description field - animated to expand when editing
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      padding: EdgeInsets.all(_isEditingDescription ? 8 : 12),
                      decoration: BoxDecoration(
                        color: _isEditingDescription 
                          ? colorScheme.surface 
                          : colorScheme.surfaceVariant.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _isEditingDescription 
                            ? colorScheme.primary.withOpacity(0.3)
                            : colorScheme.outline.withOpacity(0.2),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.notes,
                                size: 14,
                                color: colorScheme.onSurface.withOpacity(0.5),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Description',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colorScheme.onSurface.withOpacity(0.5),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const Spacer(),
                              if (widget.onUpdate != null && !_isEditingDescription)
                                InkWell(
                                  onTap: () {
                                    setState(() {
                                      _isEditingDescription = true;
                                      widget.onEditingChanged?.call(true);
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(6),
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: Icon(
                                      Icons.edit,
                                      size: 18,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                ),
                              if (_isEditingDescription)
                                InkWell(
                                  onTap: _saveDescription,
                                  borderRadius: BorderRadius.circular(6),
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: Icon(
                                      Icons.check,
                                      size: 18,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _isEditingDescription
                            ? TextField(
                                controller: _descriptionController,
                                autofocus: true,
                                maxLines: _isEditingDescription ? 8 : 3,  // Expand when editing
                                minLines: _isEditingDescription ? 6 : 1,  // Minimum lines when editing
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurface,
                                  height: 1.5,
                                ),
                                textInputAction: TextInputAction.newline,  // Allow multi-line
                                keyboardType: TextInputType.multiline,
                                decoration: InputDecoration(
                                  isDense: false,
                                  border: OutlineInputBorder(
                                    borderSide: BorderSide(color: colorScheme.outline.withOpacity(0.3)),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderSide: BorderSide(color: colorScheme.primary, width: 2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  contentPadding: const EdgeInsets.all(12),
                                  hintText: 'Add a description...',
                                  hintStyle: TextStyle(
                                    color: colorScheme.onSurface.withOpacity(0.3),
                                  ),
                                ),
                              )
                            : Text(
                                _descriptionController.text.isEmpty 
                                  ? (widget.onUpdate != null 
                                      ? 'Tap to add description...'
                                      : 'No description')
                                  : _descriptionController.text,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: _descriptionController.text.isEmpty
                                    ? colorScheme.onSurface.withOpacity(0.4)
                                    : colorScheme.onSurface,
                                  fontStyle: _descriptionController.text.isEmpty
                                    ? FontStyle.italic
                                    : FontStyle.normal,
                                ),
                              ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Action buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _openInMaps(widget.icon.latitude, widget.icon.longitude),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: colorScheme.primary,
                              side: BorderSide(color: colorScheme.primary.withOpacity(0.5)),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.map_outlined, size: 16, color: colorScheme.primary),
                                const SizedBox(width: 6),
                                const Text('Maps', style: TextStyle(fontSize: 13)),
                              ],
                            ),
                          ),
                        ),
                        if (widget.onDelete != null) ...[
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: _handleDelete,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: colorScheme.error,
                              side: BorderSide(color: colorScheme.error.withOpacity(0.5)),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.delete_outline, size: 16, color: colorScheme.error),
                                const SizedBox(width: 4),
                                const Text('Delete'),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getIconData(String iconType) {
    switch (iconType) {
      case 'pin':
        return Icons.location_on;
      case 'warning':
        return Icons.warning;
      case 'food':
        return Icons.restaurant;
      case 'car':
        return Icons.directions_car;
      case 'home':
        return Icons.home;
      case 'star':
        return Icons.star;
      case 'heart':
        return Icons.favorite;
      case 'flag':
        return Icons.flag;
      default:
        return Icons.place;
    }
  }

  Future<void> _openInMaps(double lat, double lng) async {
    try {
      String? mapChoice;
      
      if (Platform.isIOS) {
        // On iOS, show a dialog to choose between Apple Maps and Google Maps
        mapChoice = await showDialog<String>(
          context: context,
          builder: (BuildContext context) {
            final colorScheme = Theme.of(context).colorScheme;
            
            return Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 260),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.shadow.withOpacity(0.15),
                      blurRadius: 20,
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
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Apple Maps option
                      InkWell(
                        onTap: () => Navigator.of(context).pop('apple'),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceVariant.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: colorScheme.outline.withOpacity(0.2),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.map,
                                color: Colors.blue[600],
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Apple Maps',
                                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w500,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Google Maps option
                      InkWell(
                        onTap: () => Navigator.of(context).pop('google'),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceVariant.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: colorScheme.outline.withOpacity(0.2),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.map,
                                color: Colors.green[600],
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Google Maps',
                                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w500,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: colorScheme.onSurface.withOpacity(0.6),
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
        // Android - use Google Maps directly
        mapChoice = 'google';
      }

      // Now open the selected maps app
      if (mapChoice == 'apple') {
        // Apple Maps URL scheme
        final appleMapsUrl = Uri.parse(
          'maps://?q=$lat,$lng'
        );
        
        if (await canLaunchUrl(appleMapsUrl)) {
          await launchUrl(appleMapsUrl);
        } else {
          // Fallback to web-based Apple Maps
          final webAppleMapsUrl = Uri.parse(
            'https://maps.apple.com/?q=$lat,$lng'
          );
          await launchUrl(webAppleMapsUrl, mode: LaunchMode.externalApplication);
        }
      } else {
        // Google Maps
        if (Platform.isIOS) {
          // iOS Google Maps
          final googleMapsAppUrl = Uri.parse(
            'comgooglemaps://?q=$lat,$lng'
          );
          
          if (await canLaunchUrl(googleMapsAppUrl)) {
            await launchUrl(googleMapsAppUrl);
          } else {
            // Fallback to web
            final googleMapsWebUrl = Uri.parse(
              'https://www.google.com/maps/search/?api=1&query=$lat,$lng'
            );
            await launchUrl(googleMapsWebUrl, mode: LaunchMode.externalApplication);
          }
        } else {
          // Android Google Maps
          final googleMapsUrl = Uri.parse(
            'geo:$lat,$lng?q=$lat,$lng'
          );
          
          if (await canLaunchUrl(googleMapsUrl)) {
            await launchUrl(googleMapsUrl);
          } else {
            // Fallback to web
            final googleMapsWebUrl = Uri.parse(
              'https://www.google.com/maps/search/?api=1&query=$lat,$lng'
            );
            await launchUrl(googleMapsWebUrl, mode: LaunchMode.externalApplication);
          }
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not open maps application'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }
}