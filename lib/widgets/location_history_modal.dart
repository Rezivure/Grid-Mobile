import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_map_tiles_pmtiles/vector_map_tiles_pmtiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vector_renderer;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:grid_frontend/models/location_history.dart';
import 'package:grid_frontend/repositories/location_history_repository.dart';
import 'package:grid_frontend/repositories/room_location_history_repository.dart';
import 'package:grid_frontend/services/database_service.dart';
import 'package:grid_frontend/widgets/user_avatar_bloc.dart';
import 'package:grid_frontend/services/subscription_service.dart';
import 'package:matrix/matrix.dart';

class LocationHistoryModal extends StatefulWidget {
  final String userId;  // For individual history, this is userId. For groups, this is roomId
  final String userName;
  final String? avatarUrl;
  final List<String>? memberIds;  // For group history
  final bool useRoomHistory;  // Whether to use room-based history
  
  const LocationHistoryModal({
    Key? key,
    required this.userId,
    required this.userName,
    this.avatarUrl,
    this.memberIds,
    this.useRoomHistory = true,  // Default to new room-based system
  }) : super(key: key);

  @override
  State<LocationHistoryModal> createState() => _LocationHistoryModalState();
}

class _LocationHistoryModalState extends State<LocationHistoryModal> {
  late MapController _mapController;
  LocationHistory? _locationHistory;
  Map<String, LocationHistory>? _groupHistories;
  double _sliderValue = 1.0;
  DateTime? _currentTime;
  Map<String, LatLng> _currentPositions = {};
  bool _isLoading = true;
  bool _isMapLoading = true; // Separate loading state for map
  VectorTileProvider? _tileProvider;
  late vector_renderer.Theme _mapTheme;
  DateTime? _earliestTime;
  DateTime? _latestTime;
  bool _initialMapSetupDone = false;
  String? _selectedMemberId; // For group view, which member is selected
  bool _showAllMembers = false; // Toggle for showing all members vs single
  bool _mapReady = false;
  String _currentMapStyle = 'base';
  String? _satelliteMapToken;
  final SubscriptionService _subscriptionService = SubscriptionService();
  Map<String, String> _userDisplayNames = {}; // Cache for display names
  late RoomLocationHistoryRepository _roomHistoryRepo;
  
  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _roomHistoryRepo = RoomLocationHistoryRepository(DatabaseService());
    // Default to showing all members for group history
    _showAllMembers = widget.memberIds != null;
    _initializeMap();
    _loadLocationHistory();
  }
  
  Future<void> _initializeMap() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Load the user's map style preference
      _currentMapStyle = prefs.getString('selected_map_style') ?? 'base';
      
      // Check if user has subscription for satellite maps
      if (_currentMapStyle == 'satellite') {
        final hasSubscription = await _subscriptionService.hasActiveSubscription();
        if (hasSubscription) {
          // Get satellite map token
          _satelliteMapToken = await _subscriptionService.getMapToken();
        } else {
          // No subscription, fallback to base maps
          _currentMapStyle = 'base';
        }
      }
      
      // Initialize base map provider (still needed for fallback)
      if (_currentMapStyle == 'base') {
        final mapUrl = prefs.getString('maps_url') ?? 'https://map.mygrid.app/v1/protomaps.pmtiles';
        _mapTheme = ProtomapsThemes.light();
        _tileProvider = await PmTilesVectorTileProvider.fromSource(mapUrl);
      }
      
      if (mounted) {
        setState(() {
          _isMapLoading = false;
        });
      }
    } catch (e) {
      print('Error loading map provider: $e');
      if (mounted) {
        setState(() {
          _isMapLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadLocationHistory() async {
    try {
      if (widget.useRoomHistory && widget.memberIds != null) {
        // Use room-based history for groups
        final roomHistoryRepo = RoomLocationHistoryRepository(DatabaseService());
        final roomId = widget.userId; // For groups, userId is actually the roomId
        
        // Load all member histories for this room
        final histories = await roomHistoryRepo.getAllRoomHistories(roomId, userIds: widget.memberIds);
        print('Loaded room histories for ${histories.length} members out of ${widget.memberIds!.length}');
        
        // Fetch display names for members
        await _fetchUserDisplayNames(widget.memberIds!);
        
        setState(() {
          _groupHistories = histories;
          _isLoading = false;
          if (histories.isNotEmpty && !_showAllMembers && _selectedMemberId == null) {
            _selectedMemberId = histories.keys.first;
          } else if (histories.isEmpty) {
            print('No location history found for any group members in this room');
          }
          _updateSliderRange();
        });
      } else if (widget.memberIds != null) {
        // Fall back to legacy global history for groups
        final historyRepo = context.read<LocationHistoryRepository>();
        final histories = await historyRepo.getLocationHistoriesForUsers(widget.memberIds!);
        print('Loaded histories for ${histories.length} members out of ${widget.memberIds!.length}');
        
        // Fetch display names for members
        await _fetchUserDisplayNames(widget.memberIds!);
        
        setState(() {
          _groupHistories = histories;
          _isLoading = false;
          if (histories.isNotEmpty && !_showAllMembers && _selectedMemberId == null) {
            _selectedMemberId = histories.keys.first;
          } else if (histories.isEmpty) {
            print('No location history found for any group members');
          }
          _updateSliderRange();
        });
      } else {
        // Load single user history (for individual contacts - future feature)
        final historyRepo = context.read<LocationHistoryRepository>();
        final history = await historyRepo.getLocationHistory(widget.userId);
        setState(() {
          _locationHistory = history;
          _isLoading = false;
          _updateSliderRange();
        });
      }
    } catch (e) {
      print('Error loading location history: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchUserDisplayNames(List<String> userIds) async {
    try {
      final client = context.read<Client>();
      for (final userId in userIds) {
        try {
          final displayName = await client.getDisplayName(userId);
          if (displayName != null && displayName.isNotEmpty) {
            _userDisplayNames[userId] = displayName;
          } else {
            // Fallback to user ID without domain
            _userDisplayNames[userId] = userId.split(':')[0].substring(1);
          }
        } catch (e) {
          // Fallback to user ID without domain
          _userDisplayNames[userId] = userId.split(':')[0].substring(1);
        }
      }
    } catch (e) {
      print('Error fetching display names: $e');
    }
  }

  Future<void> _showClearHistoryDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        final colorScheme = Theme.of(context).colorScheme;
        return AlertDialog(
          backgroundColor: colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(
                Icons.delete_outline,
                color: colorScheme.error,
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                'Clear Location History',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          content: Text(
            'Are you sure you want to clear all location history for this group? This action cannot be undone.',
            style: TextStyle(
              color: colorScheme.onSurface.withOpacity(0.8),
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.onSurface.withOpacity(0.7),
              ),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Clear History'),
            ),
          ],
        );
      },
    );

    if (confirmed == true && widget.memberIds != null && widget.useRoomHistory) {
      try {
        // Show loading indicator
        setState(() {
          _isLoading = true;
        });

        // Clear the history for this room
        final roomId = widget.userId; // For groups, userId is actually the roomId
        await _roomHistoryRepo.deleteRoomHistory(roomId);

        // Reload the history to show empty state
        await _loadLocationHistory();

        // Show success message
        if (mounted) {
          final colorScheme = Theme.of(context).colorScheme;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Location history cleared'),
              backgroundColor: colorScheme.primary,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              margin: const EdgeInsets.all(8),
            ),
          );
        }
      } catch (e) {
        print('Error clearing location history: $e');
        setState(() {
          _isLoading = false;
        });

        if (mounted) {
          final colorScheme = Theme.of(context).colorScheme;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to clear history: $e'),
              backgroundColor: colorScheme.error,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              margin: const EdgeInsets.all(8),
            ),
          );
        }
      }
    }
  }

  void _updateSliderRange() {
    if (_locationHistory != null && _locationHistory!.points.isNotEmpty) {
      _earliestTime = _locationHistory!.points.first.timestamp;
      _latestTime = _locationHistory!.points.last.timestamp;
      _currentTime = _latestTime;
      _updateCurrentPositions();
      _setupInitialMapView();
    } else if (_groupHistories != null && _groupHistories!.isNotEmpty) {
      // For groups, always use the full time range across all members
      // This ensures the slider covers the complete history
      _earliestTime = null;
      _latestTime = null;
      
      _groupHistories!.forEach((userId, history) {
        if (history.points.isNotEmpty) {
          final firstTime = history.points.first.timestamp;
          final lastTime = history.points.last.timestamp;
          
          if (_earliestTime == null || firstTime.isBefore(_earliestTime!)) {
            _earliestTime = firstTime;
          }
          if (_latestTime == null || lastTime.isAfter(_latestTime!)) {
            _latestTime = lastTime;
          }
        }
      });
      
      _currentTime = _latestTime;
      _sliderValue = 1.0; // Start at the latest time
      _updateCurrentPositions();
      _setupInitialMapView();
    }
  }
  
  void _setupInitialMapView() {
    if (!_initialMapSetupDone && _currentPositions.isNotEmpty && mounted) {
      _initialMapSetupDone = true;
      
      // Wait for map to be ready
      if (!_mapReady) {
        // The onMapReady callback will handle fitting the view
        return;
      }
      
      try {
        final points = _currentPositions.values.toList();
        if (points.length == 1) {
          // For single point, just center on it
          _mapController.move(points.first, 15.0);
        } else if (points.length > 1) {
          // For multiple points, fit bounds with more padding for group view
          final bounds = LatLngBounds.fromPoints(points);
          _mapController.fitCamera(
            CameraFit.bounds(
              bounds: bounds,
              padding: _showAllMembers 
                  ? const EdgeInsets.all(80)  // More padding for group view
                  : const EdgeInsets.all(50),
            ),
          );
        }
      } catch (e) {
        print('Error setting up initial map view: $e');
      }
    }
  }

  void _updateCurrentPositions() {
    if (_locationHistory != null && _currentTime != null) {
      // Single user
      final position = _getPositionAtTime(_locationHistory!, _currentTime!);
      if (position != null) {
        _currentPositions[widget.userId] = position;
        // Pan map to follow the user
        _mapController.move(position, _mapController.camera.zoom);
      }
    } else if (_groupHistories != null && _currentTime != null) {
      // Multiple users
      final newPositions = <String, LatLng>{};
      if (_showAllMembers) {
        // Show all members
        _groupHistories!.forEach((userId, history) {
          final position = _getPositionAtTime(history, _currentTime!);
          if (position != null) {
            newPositions[userId] = position;
          }
        });
      } else if (_selectedMemberId != null && _groupHistories!.containsKey(_selectedMemberId!)) {
        // Show only selected member
        final selectedHistory = _groupHistories![_selectedMemberId!]!;
        
        // If current time is beyond this user's history, use their last point
        final userLatestTime = selectedHistory.points.isNotEmpty 
            ? selectedHistory.points.last.timestamp 
            : _currentTime!;
        final effectiveTime = _currentTime!.isAfter(userLatestTime) 
            ? userLatestTime 
            : _currentTime!;
            
        final position = _getPositionAtTime(selectedHistory, effectiveTime);
        if (position != null) {
          newPositions[_selectedMemberId!] = position;
          // Pan map to follow the selected member
          _mapController.move(position, _mapController.camera.zoom);
        }
      }
      _currentPositions = newPositions;
    }
  }

  LatLng? _getPositionAtTime(LocationHistory history, DateTime time) {
    if (history.points.isEmpty) return null;
    
    // Get all points up to the current time
    final validPoints = history.points
        .where((p) => p.timestamp.isBefore(time) || p.timestamp.isAtSameMomentAs(time))
        .toList();
    
    if (validPoints.isEmpty) {
      // If no points before this time, use the first point
      return LatLng(history.points.first.latitude, history.points.first.longitude);
    }
    
    // Return the last valid point (most recent up to current time)
    final lastPoint = validPoints.last;
    return LatLng(lastPoint.latitude, lastPoint.longitude);
  }

  List<LatLng> _getPathForUser(LocationHistory history, DateTime endTime) {
    final validPoints = history.points
        .where((p) => p.timestamp.isBefore(endTime) || p.timestamp.isAtSameMomentAs(endTime))
        .toList();
    
    // Smart sampling - reduce points if there are too many for performance
    // But keep more detail than before
    if (validPoints.length > 500) {
      // Sample every Nth point based on total count, but keep key points
      final sampleRate = (validPoints.length / 300).ceil(); // Target ~300 points
      final sampled = <LocationPoint>[];
      
      for (int i = 0; i < validPoints.length; i++) {
        if (i == 0 || i == validPoints.length - 1) {
          // Always keep first and last points
          sampled.add(validPoints[i]);
        } else if (i % sampleRate == 0) {
          // Sample at regular intervals
          sampled.add(validPoints[i]);
        } else if (i > 0 && i < validPoints.length - 1) {
          // Keep points that show significant direction changes
          final prev = validPoints[i - 1];
          final curr = validPoints[i];
          final next = validPoints[i + 1];
          
          final angle1 = _calculateBearing(
            LatLng(prev.latitude, prev.longitude),
            LatLng(curr.latitude, curr.longitude),
          );
          final angle2 = _calculateBearing(
            LatLng(curr.latitude, curr.longitude),
            LatLng(next.latitude, next.longitude),
          );
          
          final angleDiff = (angle2 - angle1).abs();
          if (angleDiff > 30) { // Keep points with >30 degree direction change
            sampled.add(curr);
          }
        }
      }
      
      return sampled.map((p) => LatLng(p.latitude, p.longitude)).toList();
    } else {
      // If less than 500 points, show all of them for detail
      return validPoints.map((p) => LatLng(p.latitude, p.longitude)).toList();
    }
  }
  
  double _calculateBearing(LatLng start, LatLng end) {
    final dLon = end.longitude - start.longitude;
    final y = sin(dLon * pi / 180) * cos(end.latitude * pi / 180);
    final x = cos(start.latitude * pi / 180) * sin(end.latitude * pi / 180) -
        sin(start.latitude * pi / 180) * cos(end.latitude * pi / 180) * cos(dLon * pi / 180);
    return atan2(y, x) * 180 / pi;
  }
  
  List<Polyline> _getPolylinesForGroup() {
    final colorScheme = Theme.of(context).colorScheme;
    
    if (_showAllMembers && _groupHistories != null && _currentTime != null) {
      // Show all members
      return _groupHistories!.entries.map((entry) {
        final color = _getUserColor(entry.key);
        return Polyline(
          points: _getPathForUser(entry.value, _currentTime!),
          strokeWidth: 3.0,
          color: color,
        );
      }).toList();
    } else if (!_showAllMembers && 
               _selectedMemberId != null && 
               _groupHistories != null &&
               _groupHistories!.containsKey(_selectedMemberId!) &&
               _currentTime != null) {
      // Show single selected member
      final selectedHistory = _groupHistories![_selectedMemberId!]!;
      
      // If current time is beyond this user's history, use their last point
      final userLatestTime = selectedHistory.points.isNotEmpty 
          ? selectedHistory.points.last.timestamp 
          : _currentTime!;
      final effectiveTime = _currentTime!.isAfter(userLatestTime) 
          ? userLatestTime 
          : _currentTime!;
      
      return [
        Polyline(
          points: _getPathForUser(selectedHistory, effectiveTime),
          strokeWidth: 3.0,
          color: colorScheme.primary,
        ),
      ];
    }
    
    // Return empty list if no data
    return [];
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inDays == 0) {
      return 'Today ${DateFormat('h:mm a').format(dateTime)}';
    } else if (difference.inDays == 1) {
      return 'Yesterday ${DateFormat('h:mm a').format(dateTime)}';
    } else if (difference.inDays < 7) {
      return DateFormat('EEEE h:mm a').format(dateTime);
    } else {
      return DateFormat('MMM d, h:mm a').format(dateTime);
    }
  }
  
  String _formatTimeRange(DateTime? start, DateTime? end) {
    if (start == null || end == null) return '';
    
    final duration = end.difference(start);
    
    if (duration.inMinutes < 60) {
      return '${duration.inMinutes} minutes';
    } else if (duration.inHours < 24) {
      final hours = duration.inHours;
      final minutes = duration.inMinutes % 60;
      if (minutes > 0) {
        return '$hours hour${hours > 1 ? 's' : ''} $minutes min';
      } else {
        return '$hours hour${hours > 1 ? 's' : ''}';
      }
    } else {
      final days = duration.inDays;
      final hours = duration.inHours % 24;
      if (hours > 0) {
        return '$days day${days > 1 ? 's' : ''} $hours hour${hours > 1 ? 's' : ''}';
      } else {
        return '$days day${days > 1 ? 's' : ''}';
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: colorScheme.onSurfaceVariant.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                if (widget.memberIds == null) ...[
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: colorScheme.primary.withOpacity(0.1),
                    child: UserAvatarBloc(
                      userId: widget.userId,
                      size: 40,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.memberIds != null ? 'Group History' : '${widget.userName}\'s History',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (_currentTime != null)
                        Text(
                          _formatDateTime(_currentTime!),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                // Clear history button for groups
                if (widget.memberIds != null)
                  IconButton(
                    icon: Icon(
                      Icons.delete_outline,
                      color: colorScheme.error,
                    ),
                    onPressed: _showClearHistoryDialog,
                    tooltip: 'Clear History',
                  ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          
          // Avatar selector for groups
          if (!_isLoading && !_isMapLoading && _groupHistories != null && _groupHistories!.isNotEmpty)
            Container(
              height: 100,
              decoration: BoxDecoration(
                color: colorScheme.surface,
                border: Border(
                  bottom: BorderSide(
                    color: colorScheme.outline.withOpacity(0.2),
                  ),
                ),
              ),
              child: Row(
                children: [
                  // Avatar scroll list
                  Expanded(
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      itemCount: widget.memberIds?.length ?? 0,
                      itemBuilder: (context, index) {
                        final memberId = widget.memberIds![index];
                        final isSelected = _showAllMembers || memberId == _selectedMemberId;
                        final hasHistory = _groupHistories!.containsKey(memberId);
                        
                        return Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: hasHistory ? () {
                                  setState(() {
                                    _showAllMembers = false;
                                    _selectedMemberId = memberId;
                                    _updateSliderRange();
                                  });
                                } : null,
                                child: Stack(
                                  children: [
                                    Container(
                                      width: 56,
                                      height: 56,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: isSelected 
                                              ? colorScheme.primary 
                                              : Colors.transparent,
                                          width: 2,
                                        ),
                                      ),
                                      padding: const EdgeInsets.all(2),
                                      child: Opacity(
                                        opacity: hasHistory ? 1.0 : 0.5,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: colorScheme.primary.withOpacity(0.1),
                                          ),
                                          child: ClipOval(
                                            child: UserAvatarBloc(
                                              userId: memberId,
                                              size: 48,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (!hasHistory)
                                      Positioned(
                                        bottom: 0,
                                        right: 0,
                                        child: Container(
                                          padding: const EdgeInsets.all(2),
                                          decoration: BoxDecoration(
                                            color: colorScheme.surface,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            Icons.location_off,
                                            size: 12,
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 4),
                              SizedBox(
                                width: 70,
                                child: Text(
                                  _userDisplayNames[memberId] ?? memberId.split(':')[0].substring(1),
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: isSelected 
                                        ? colorScheme.primary 
                                        : colorScheme.onSurfaceVariant,
                                    fontSize: 10,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  // Group view button with tooltip
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Tooltip(
                          message: _showAllMembers 
                              ? 'Tap to view individual member\nCurrently showing: All members' 
                              : 'Tap to view all members together\nCurrently showing: Individual',
                          preferBelow: false,  // Show tooltip above the button
                          verticalOffset: -10,  // Adjust position
                          textStyle: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          triggerMode: TooltipTriggerMode.longPress,  // Show on long press
                          waitDuration: const Duration(milliseconds: 100),  // Faster show
                          showDuration: const Duration(seconds: 3),  // Show longer
                          child: IconButton(
                            onPressed: () {
                              setState(() {
                                _showAllMembers = !_showAllMembers;
                                _updateSliderRange();
                                if (_showAllMembers) {
                                  _fitAllMembersInView();
                                }
                              });
                            },
                            icon: Icon(
                              _showAllMembers ? Icons.person : Icons.groups,
                              color: _showAllMembers 
                                  ? colorScheme.primary 
                                  : colorScheme.onSurfaceVariant,
                              size: 24,
                            ),
                            style: IconButton.styleFrom(
                              backgroundColor: _showAllMembers 
                                  ? colorScheme.primary.withOpacity(0.1)
                                  : colorScheme.surfaceVariant.withOpacity(0.5),
                            ),
                          ),
                        ),
                        Text(
                          _showAllMembers ? 'Group' : 'Individual',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          
          // Map
          Expanded(
            child: Stack(
              children: [
                if (_isLoading || _isMapLoading)
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(
                          color: colorScheme.primary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _isLoading ? 'Loading history...' : 'Preparing map...',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  )
                else if ((_locationHistory == null && _groupHistories == null) || 
                         (_locationHistory == null && _groupHistories != null && _groupHistories!.isEmpty))
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.location_off,
                          size: 64,
                          color: colorScheme.onSurfaceVariant.withOpacity(0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No location history available',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  )
                else if (_currentMapStyle == 'base' && _tileProvider == null)
                  Center(
                    child: CircularProgressIndicator(
                      color: colorScheme.primary,
                    ),
                  )
                else if ((_currentMapStyle == 'base' && _tileProvider != null) || 
                         (_currentMapStyle == 'satellite' && _satelliteMapToken != null))
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _currentPositions.isNotEmpty 
                            ? (_showAllMembers && _currentPositions.length > 1
                                ? _calculateCenterPoint(_currentPositions.values.toList())
                                : _currentPositions.values.first)
                            : const LatLng(37.7749, -122.4194), // Default to SF
                        initialZoom: _showAllMembers ? 9.0 : 11.0,
                        onMapReady: () {
                          setState(() {
                            _mapReady = true;
                          });
                          // Now that map is ready, fit all members if in group view
                          if (_showAllMembers && _currentPositions.isNotEmpty) {
                            Future.delayed(const Duration(milliseconds: 100), () {
                              _fitAllMembersInView();
                            });
                          }
                        },
                      ),
                      children: [
                        // Map tiles - either base or satellite
                        if (_currentMapStyle == 'base' && _tileProvider != null)
                          VectorTileLayer(
                            theme: _mapTheme,
                            tileProviders: TileProviders({'protomaps': _tileProvider!}),
                            fileCacheTtl: const Duration(days: 14),
                            memoryTileDataCacheMaxSize: 80,
                            memoryTileCacheMaxSize: 100,
                            concurrency: 5,
                          )
                        else if (_currentMapStyle == 'satellite' && _satelliteMapToken != null)
                          TileLayer(
                            urlTemplate: '${dotenv.env['SAT_MAPS_URL'] ?? 'https://sat-maps.mygrid.app'}/tiles/alidade_satellite/{z}/{x}/{y}.png',
                            tileProvider: NetworkTileProvider(
                              headers: {
                                'Authorization': 'Bearer $_satelliteMapToken',
                              },
                            ),
                            maxZoom: 20,
                            maxNativeZoom: 20,
                            tileSize: 256,
                          ),
                        
                        // Draw paths
                        if (_locationHistory != null && _currentTime != null)
                          PolylineLayer(
                            polylines: [
                              Polyline(
                                points: _getPathForUser(_locationHistory!, _currentTime!),
                                strokeWidth: 3.0,
                                color: colorScheme.primary,
                              ),
                            ],
                          )
                        else if (_groupHistories != null && _currentTime != null)
                          PolylineLayer(
                            polylines: _getPolylinesForGroup(),
                          ),
                        
                        // Draw current positions
                        MarkerLayer(
                          markers: _currentPositions.entries.map((entry) {
                            return Marker(
                              point: entry.value,
                              width: 50,
                              height: 50,
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Container(
                                    width: 50,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.2),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                  ),
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor: colorScheme.primary.withOpacity(0.1),
                                    child: UserAvatarBloc(
                                      userId: entry.key,
                                      size: 40,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                
              ],
            ),
          ),
          
          // Timeline slider
          if (!_isLoading && !_isMapLoading &&
              ((_locationHistory != null && _locationHistory!.points.isNotEmpty) ||
               (_groupHistories != null && _groupHistories!.isNotEmpty)))
            Container(
              decoration: BoxDecoration(
                color: colorScheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                  child: Column(
                    children: [
                      // Time range indicator
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.timeline,
                              size: 16,
                              color: colorScheme.onPrimaryContainer,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _formatTimeRange(_earliestTime, _latestTime),
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Slider with custom styling
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 4,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 8,
                            elevation: 2,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 16,
                          ),
                          activeTrackColor: colorScheme.primary,
                          inactiveTrackColor: colorScheme.primary.withOpacity(0.2),
                          thumbColor: colorScheme.primary,
                          overlayColor: colorScheme.primary.withOpacity(0.12),
                        ),
                        child: Slider(
                          value: _sliderValue,
                          onChanged: (value) {
                            setState(() {
                              _sliderValue = value;
                              _updateTimeFromSlider();
                            });
                          },
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Start and end labels
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _earliestTime != null 
                                ? DateFormat('MMM d, h:mm a').format(_earliestTime!)
                                : 'Start',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant.withOpacity(0.7),
                            ),
                          ),
                          Text(
                            _latestTime != null 
                                ? DateFormat('MMM d, h:mm a').format(_latestTime!)
                                : 'Now',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant.withOpacity(0.7),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _updateTimeFromSlider() {
    try {
      if (_locationHistory != null && _locationHistory!.points.isNotEmpty) {
        final points = _locationHistory!.points;
        if (points.length == 1) {
          _currentTime = points.first.timestamp;
          _updateCurrentPositions();
          return;
        }
        
        final startTime = points.first.timestamp;
        final endTime = points.last.timestamp;
        final duration = endTime.difference(startTime);
        
        // Check if slider is at maximum (accounting for floating point precision)
        if (_sliderValue >= 0.999) {
          _currentTime = endTime;
          _updateCurrentPositions();
        } else if (duration.inMilliseconds > 0) {
          _currentTime = startTime.add(Duration(
            milliseconds: (duration.inMilliseconds * _sliderValue).toInt(),
          ));
          _updateCurrentPositions();
        }
      } else if (_groupHistories != null && _earliestTime != null && _latestTime != null) {
        // Check if slider is at maximum (accounting for floating point precision)
        if (_sliderValue >= 0.999) {
          _currentTime = _latestTime;
          _updateCurrentPositions();
        } else {
          // Use the cached earliest and latest times for consistency
          final duration = _latestTime!.difference(_earliestTime!);
          
          if (duration.inMilliseconds > 0) {
            _currentTime = _earliestTime!.add(Duration(
              milliseconds: (duration.inMilliseconds * _sliderValue).toInt(),
            ));
            _updateCurrentPositions();
          } else {
            _currentTime = _earliestTime;
            _updateCurrentPositions();
          }
        }
      }
    } catch (e) {
      print('Error updating time from slider: $e');
    }
  }

  Color _getUserColor(String userId) {
    // Generate a consistent color for each user
    final hash = userId.hashCode;
    final hue = (hash % 360).toDouble();
    return HSLColor.fromAHSL(1.0, hue, 0.6, 0.5).toColor();
  }
  
  void _fitAllMembersInView() {
    if (_currentPositions.isNotEmpty && mounted && _mapReady) {
      try {
        final points = _currentPositions.values.toList();
        if (points.length == 1) {
          _mapController.move(points.first, 15.0);
        } else if (points.length > 1) {
          final bounds = LatLngBounds.fromPoints(points);
          _mapController.fitCamera(
            CameraFit.bounds(
              bounds: bounds,
              padding: const EdgeInsets.all(80),
            ),
          );
        }
      } catch (e) {
        print('Error fitting all members in view: $e');
      }
    }
  }
  
  LatLng _calculateCenterPoint(List<LatLng> points) {
    if (points.isEmpty) return const LatLng(37.7749, -122.4194);
    if (points.length == 1) return points.first;
    
    double sumLat = 0;
    double sumLng = 0;
    
    for (final point in points) {
      sumLat += point.latitude;
      sumLng += point.longitude;
    }
    
    return LatLng(sumLat / points.length, sumLng / points.length);
  }
}