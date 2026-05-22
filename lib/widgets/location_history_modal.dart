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
import 'package:grid_frontend/services/in_app_notifier.dart';
import 'package:grid_frontend/widgets/user_avatar_bloc.dart';
import 'package:grid_frontend/services/subscription_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:grid_frontend/styles/tokens.dart';
import 'package:grid_frontend/styles/grid_colors.dart';
import 'package:grid_frontend/widgets/grid/grid_button.dart';
import 'package:grid_frontend/widgets/grid/grid_mono.dart';
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
  int _playbackSpeed = 1; // 1x / 2x / 4x — UI chrome to match design spec
  static const List<int> _speedOptions = [1, 2, 4];
  
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
          final profileData = await client.getProfileField(userId, 'displayname');
          final displayName = profileData?['displayname'] as String?;
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
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.9,
            ),
            decoration: BoxDecoration(
              color: context.gridColors.surface,
              borderRadius: BorderRadius.circular(GridTokens.rXl),
              border: Border.all(color: context.gridColors.hairline),
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
                          Icons.delete_outline,
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
                              'Clear location history',
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
                              "This action cannot be undone.",
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
                    'Are you sure you want to clear all location history for this group?',
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
                          label: 'Clear',
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
          InAppNotifier.instance.show(
            title: 'Location history cleared',
            variant: InAppNotificationVariant.success,
          );
        }
      } catch (e) {
        print('Error clearing location history: $e');
        setState(() {
          _isLoading = false;
        });

        if (mounted) {
          InAppNotifier.instance.show(
            title: 'Failed to clear history',
            message: '$e',
            variant: InAppNotificationVariant.error,
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
          _mapController.move(points.first, 12.0);
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

  /// Compact mono-style total duration, e.g. "2H 14M" or "45M" or "4D".
  String _formatMonoDuration(DateTime? start, DateTime? end) {
    if (start == null || end == null) return '--';
    final d = end.difference(start);
    if (d.inMinutes < 60) return '${d.inMinutes}M';
    if (d.inHours < 24) {
      final h = d.inHours;
      final m = d.inMinutes % 60;
      if (m == 0) return '${h}H';
      return '${h}H ${m}M';
    }
    final days = d.inDays;
    final hours = d.inHours % 24;
    if (hours == 0) return '${days}D';
    return '${days}D ${hours}H';
  }

  /// Format the subtitle next to the title — e.g. "Today · 2h 14m".
  String _formatHeaderSubtitle() {
    if (_earliestTime == null || _latestTime == null) return '';
    final now = DateTime.now();
    final start = _earliestTime!;
    final dayDiff = now.difference(start).inDays;
    String dayLabel;
    if (dayDiff == 0 && now.day == start.day) {
      dayLabel = 'Today';
    } else if (dayDiff == 1 ||
        (dayDiff == 0 && now.day != start.day)) {
      dayLabel = 'Yesterday';
    } else if (dayDiff < 7) {
      dayLabel = DateFormat('EEEE').format(start);
    } else {
      dayLabel = DateFormat('MMM d').format(start);
    }
    final duration = _latestTime!.difference(start);
    String durLabel;
    if (duration.inMinutes < 60) {
      durLabel = '${duration.inMinutes}m';
    } else if (duration.inHours < 24) {
      final h = duration.inHours;
      final m = duration.inMinutes % 60;
      durLabel = m > 0 ? '${h}h ${m}m' : '${h}h';
    } else {
      durLabel = '${duration.inDays}d ago';
    }
    return '$dayLabel  ·  $durLabel';
  }

  /// Approximate "stops" — clusters of consecutive points within a small
  /// radius. Used only for the mono status pill ("2H 14M · 8 STOPS").
  int _countStops() {
    Iterable<LocationHistory> sources;
    if (_locationHistory != null) {
      sources = [_locationHistory!];
    } else if (_groupHistories != null) {
      sources = _groupHistories!.values;
    } else {
      return 0;
    }
    var total = 0;
    for (final h in sources) {
      if (h.points.length < 2) continue;
      var stops = 0;
      var inStop = false;
      for (var i = 1; i < h.points.length; i++) {
        final a = h.points[i - 1];
        final b = h.points[i];
        final dLat = (a.latitude - b.latitude).abs();
        final dLng = (a.longitude - b.longitude).abs();
        final isStill = dLat < 0.0003 && dLng < 0.0003;
        if (isStill && !inStop) {
          stops++;
          inStop = true;
        } else if (!isStill) {
          inStop = false;
        }
      }
      total += stops;
    }
    return total;
  }

  String _formatMonoClock(DateTime t) => DateFormat('h:mm').format(t);
  String _formatMonoMeridiem(DateTime t) =>
      DateFormat('a').format(t);

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
    
    final isGroup = widget.memberIds != null;
    final headerTitle = isGroup
        ? '${widget.userName} · history'
        : '${widget.userName}’s history';

    return Container(
      decoration: BoxDecoration(
        color: context.gridColors.bg,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(GridTokens.r2Xl),
          topRight: Radius.circular(GridTokens.r2Xl),
        ),
      ),
      child: Column(
        children: [
          // Grab handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: context.gridColors.hairlineStrong,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // TopBar — close (left), title + mono subtitle (center), trash/more (right)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _ChromeIconBtn(
                  icon: Icons.close,
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        headerTitle,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: context.gridColors.text,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.015,
                        ),
                      ),
                      const SizedBox(height: 2),
                      if (_earliestTime != null && _latestTime != null)
                        GridMono(
                          _formatHeaderSubtitle(),
                          color: context.gridColors.text3,
                          size: 10.5,
                          letterSpacing: 0.08,
                          uppercase: false,
                        )
                      else
                        GridMono(
                          'Loading',
                          color: context.gridColors.text3,
                          size: 10.5,
                          letterSpacing: 0.08,
                          uppercase: false,
                        ),
                    ],
                  ),
                ),
                if (isGroup)
                  _ChromeIconBtn(
                    icon: Icons.delete_outline,
                    iconColor: context.gridColors.danger,
                    onPressed: _showClearHistoryDialog,
                  )
                else
                  _ChromeIconBtn(
                    icon: Icons.more_horiz_rounded,
                    onPressed: () {},
                  ),
              ],
            ),
          ),
          
          // Member strip — group mode. First tile = ALL.
          if (!_isLoading && !_isMapLoading && _groupHistories != null && _groupHistories!.isNotEmpty)
            SizedBox(
              height: 86,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
                itemCount: (widget.memberIds?.length ?? 0) + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    final active = _showAllMembers;
                    return _MemberTile(
                      active: active,
                      underlineColor: context.gridColors.mint,
                      label: 'All',
                      labelColor: active ? context.gridColors.mint : context.gridColors.text2,
                      onTap: () {
                        setState(() {
                          _showAllMembers = true;
                          _selectedMemberId = null;
                          _updateSliderRange();
                          _fitAllMembersInView();
                        });
                      },
                      child: const _AllTileContent(),
                    );
                  }

                  final memberId = widget.memberIds![index - 1];
                  final hasHistory = _groupHistories!.containsKey(memberId);
                  final active = !_showAllMembers && memberId == _selectedMemberId;
                  final memberColor = _getUserColor(memberId);
                  final memberLabel = _userDisplayNames[memberId] ??
                      memberId.split(':').first.replaceFirst('@', '');

                  return _MemberTile(
                    active: active,
                    underlineColor: memberColor,
                    label: memberLabel,
                    labelColor: active ? context.gridColors.text : context.gridColors.text2,
                    onTap: hasHistory
                        ? () {
                            setState(() {
                              _showAllMembers = false;
                              _selectedMemberId = memberId;
                              _updateSliderRange();
                              if (_currentPositions.containsKey(memberId)) {
                                _mapController.move(
                                  _currentPositions[memberId]!,
                                  12.0,
                                );
                              }
                            });
                          }
                        : null,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Opacity(
                          opacity: hasHistory ? 1.0 : 0.45,
                          child: ClipOval(
                            child: UserAvatarBloc(
                              userId: memberId,
                              size: 48,
                            ),
                          ),
                        ),
                        if (!hasHistory)
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: context.gridColors.surface,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.location_off,
                                size: 10,
                                color: context.gridColors.text3,
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          
          // Map area — rLg rounded, surface2 bg
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(14, 4, 14, 10),
              decoration: BoxDecoration(
                color: context.gridColors.surface2,
                borderRadius: BorderRadius.circular(GridTokens.rLg),
                border: Border.all(color: context.gridColors.hairline),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                if (_isLoading || _isMapLoading)
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(
                          color: context.gridColors.mint,
                        ),
                        const SizedBox(height: 16),
                        GridMono(
                          _isLoading ? 'Loading history' : 'Preparing map',
                          color: context.gridColors.text3,
                          size: 11,
                          letterSpacing: 0.08,
                          uppercase: false,
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
                          size: 56,
                          color: context.gridColors.text3,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No location history available',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: context.gridColors.text2,
                          ),
                        ),
                      ],
                    ),
                  )
                else if (_currentMapStyle == 'base' && _tileProvider == null)
                  Center(
                    child: CircularProgressIndicator(
                      color: context.gridColors.mint,
                    ),
                  )
                else if ((_currentMapStyle == 'base' && _tileProvider != null) ||
                         (_currentMapStyle == 'satellite' && _satelliteMapToken != null))
                  ClipRRect(
                    borderRadius: BorderRadius.circular(GridTokens.rLg),
                    child: FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _currentPositions.isNotEmpty
                            ? (_showAllMembers && _currentPositions.length > 1
                                ? _calculateSmartZoom(_currentPositions.values.toList()).center
                                : _currentPositions.values.first)
                            : const LatLng(37.7749, -122.4194), // Default to SF
                        initialZoom: _currentPositions.isNotEmpty && _showAllMembers
                            ? _calculateSmartZoom(_currentPositions.values.toList()).zoom
                            : 10.0,
                        minZoom: 2.0,  // Allow zooming out to see whole continent
                        maxZoom: 16.0, // Prevent zooming in too close (street level)
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
          ),

          // Timeline scrubber — surface bg, top hairline
          if (!_isLoading && !_isMapLoading &&
              ((_locationHistory != null && _locationHistory!.points.isNotEmpty) ||
               (_groupHistories != null && _groupHistories!.isNotEmpty)))
            Container(
              decoration: BoxDecoration(
                color: context.gridColors.surface,
                border: Border(
                  top: BorderSide(color: context.gridColors.hairline),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
                  child: Column(
                    children: [
                      // Status row: mono pill (duration + stops) · speed pills
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: context.gridColors.surface2,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: context.gridColors.hairline),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.access_time_rounded,
                                  size: 12,
                                  color: context.gridColors.mint,
                                ),
                                const SizedBox(width: 6),
                                GridMono(
                                  '${_formatMonoDuration(_earliestTime, _latestTime)} · ${_countStops()} STOPS',
                                  color: context.gridColors.text2,
                                  size: 10.5,
                                  letterSpacing: 0.08,
                                ),
                              ],
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final speed in _speedOptions) ...[
                                _SpeedPill(
                                  speed: speed,
                                  active: _playbackSpeed == speed,
                                  onTap: () => setState(() => _playbackSpeed = speed),
                                ),
                                if (speed != _speedOptions.last)
                                  const SizedBox(width: 6),
                              ],
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      // Slider — mint track + white thumb with mint-soft halo
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          activeTrackColor: context.gridColors.mint,
                          inactiveTrackColor: context.gridColors.surface3,
                          thumbColor: Colors.white,
                          overlayColor: context.gridColors.mintSoft,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 8,
                            elevation: 0,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 16,
                          ),
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
                      // Mono start · current (mint, 600) · end
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _ScrubberTimeLabel(
                            top: _earliestTime != null
                                ? _formatMonoClock(_earliestTime!)
                                : '--:--',
                            bottom: _earliestTime != null
                                ? _formatMonoMeridiem(_earliestTime!)
                                : '',
                            color: context.gridColors.text3,
                          ),
                          _ScrubberTimeLabel(
                            top: _currentTime != null
                                ? _formatMonoClock(_currentTime!)
                                : '--:--',
                            bottom: _currentTime != null
                                ? _formatMonoMeridiem(_currentTime!)
                                : '',
                            color: context.gridColors.mint,
                            bold: true,
                          ),
                          _ScrubberTimeLabel(
                            top: _latestTime != null
                                ? _formatMonoClock(_latestTime!)
                                : '--:--',
                            bottom: _latestTime != null
                                ? _formatMonoMeridiem(_latestTime!)
                                : '',
                            color: context.gridColors.text3,
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
          // Single point - fixed zoom 6
          _mapController.move(points.first, 6.0);
        } else if (points.length > 1) {
          // Calculate smart zoom like main map
          final result = _calculateSmartZoom(points);
          _mapController.moveAndRotate(result.center, result.zoom, 0);
        }
      } catch (e) {
        print('Error fitting all members in view: $e');
      }
    }
  }

  // Smart zoom calculation matching main map logic
  ({LatLng center, double zoom}) _calculateSmartZoom(List<LatLng> points) {
    if (points.isEmpty) {
      return (center: const LatLng(37.7749, -122.4194), zoom: 4.0);
    }

    if (points.length == 1) {
      return (center: points.first, zoom: 8.0);  // Single user
    }

    // Calculate bounds
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final point in points) {
      minLat = minLat < point.latitude ? minLat : point.latitude;
      maxLat = maxLat > point.latitude ? maxLat : point.latitude;
      minLng = minLng < point.longitude ? minLng : point.longitude;
      maxLng = maxLng > point.longitude ? maxLng : point.longitude;
    }

    // Calculate center
    final centerLat = (minLat + maxLat) / 2;
    final centerLng = (minLng + maxLng) / 2;
    final centerPoint = LatLng(centerLat, centerLng);

    // Calculate span
    final latDiff = maxLat - minLat;
    final lngDiff = maxLng - minLng;
    final maxDiff = latDiff > lngDiff ? latDiff : lngDiff;

    // Calculate zoom with reduced levels for smaller window
    double zoomLevel;
    if (maxDiff < 0.01) {
      zoomLevel = 12.0; // Very close together
    } else if (maxDiff < 0.05) {
      zoomLevel = 10.0; // City area
    } else if (maxDiff < 0.1) {
      zoomLevel = 8.0; // Metro area
    } else if (maxDiff < 0.5) {
      zoomLevel = 6.0; // Multi-city region
    } else if (maxDiff < 2.0) {
      zoomLevel = 5.0; // State-sized area
    } else if (maxDiff < 10.0) {
      zoomLevel = 4.0; // Multi-state
    } else if (maxDiff < 50.0) {
      zoomLevel = 3.0; // Country-sized (USA coast to coast)
    } else {
      zoomLevel = 2.0; // Continental/Intercontinental
    }

    // Reduce zoom by 0.5 for a bit of extra margin in the small window
    zoomLevel = zoomLevel - 0.5;

    // Now we can go down to 2.0 since we changed minZoom
    if (zoomLevel < 2.0) zoomLevel = 2.0;
    if (zoomLevel > 14.0) zoomLevel = 14.0;

    return (center: centerPoint, zoom: zoomLevel);
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

// ─── Local chrome atoms ─────────────────────────────────────────────────────

/// Small surface-bg square button used in the top bar (close / more / trash).
class _ChromeIconBtn extends StatelessWidget {
  const _ChromeIconBtn({
    required this.icon,
    required this.onPressed,
    this.iconColor,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(GridTokens.rMd),
        child: Ink(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: context.gridColors.surface2,
            borderRadius: BorderRadius.circular(GridTokens.rMd),
            border: Border.all(color: context.gridColors.hairline),
          ),
          child: Icon(
            icon,
            size: 18,
            color: iconColor ?? context.gridColors.text,
          ),
        ),
      ),
    );
  }
}

/// Avatar tile in the member strip — 52pt with optional 2pt mint ring + 16×2
/// colored pill underline when active.
class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.active,
    required this.underlineColor,
    required this.label,
    required this.labelColor,
    required this.child,
    this.onTap,
  });

  final bool active;
  final Color underlineColor;
  final String label;
  final Color labelColor;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  width: 2,
                  color: active ? context.gridColors.mint : Colors.transparent,
                ),
              ),
              child: ClipOval(child: child),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 10.5,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                letterSpacing: -0.01,
                color: labelColor,
              ),
            ),
            const SizedBox(height: 3),
            // Underline pill — visible only when active.
            Container(
              width: 16,
              height: 2,
              decoration: BoxDecoration(
                color: active ? underlineColor : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "ALL" content tile — mint text on surface2.
class _AllTileContent extends StatelessWidget {
  const _AllTileContent();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.gridColors.surface2,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        'ALL',
        style: TextStyle(
          fontFamily: 'GeistMono',
          color: context.gridColors.mint,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.12,
        ),
      ),
    );
  }
}

/// Speed pill — 1× / 2× / 4× in the scrubber row.
class _SpeedPill extends StatelessWidget {
  const _SpeedPill({
    required this.speed,
    required this.active,
    required this.onTap,
  });

  final int speed;
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
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: active ? context.gridColors.mintSoft : context.gridColors.surface2,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: active ? context.gridColors.mint : context.gridColors.hairline,
            ),
          ),
          child: GridMono(
            '${speed}x',
            color: active ? context.gridColors.mint : context.gridColors.text2,
            size: 10.5,
            letterSpacing: 0.04,
            uppercase: false,
            weight: active ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// Two-line mono time label (e.g. "6:42" over "AM") below the scrubber.
class _ScrubberTimeLabel extends StatelessWidget {
  const _ScrubberTimeLabel({
    required this.top,
    required this.bottom,
    required this.color,
    this.bold = false,
  });

  final String top;
  final String bottom;
  final Color color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GridMono(
          top,
          color: color,
          size: 13,
          letterSpacing: 0.02,
          uppercase: false,
          weight: bold ? FontWeight.w600 : FontWeight.w500,
        ),
        const SizedBox(height: 2),
        GridMono(
          bottom,
          color: color.withOpacity(0.8),
          size: 9,
          letterSpacing: 0.08,
        ),
      ],
    );
  }
}