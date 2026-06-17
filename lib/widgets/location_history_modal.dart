import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:grid_frontend/models/location_history.dart';
import 'package:grid_frontend/repositories/location_history_repository.dart';
import 'package:grid_frontend/repositories/room_location_history_repository.dart';
import 'package:grid_frontend/screens/map/grid_map_style.dart';
import 'package:grid_frontend/services/database_service.dart';
import 'package:grid_frontend/services/in_app_notifier.dart';
import 'package:grid_frontend/widgets/user_avatar_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:grid_frontend/styles/tokens.dart';
import 'package:grid_frontend/styles/grid_colors.dart';
import 'package:grid_frontend/widgets/grid/grid_button.dart';
import 'package:grid_frontend/widgets/grid/grid_mono.dart';
import 'package:grid_frontend/widgets/grid/grid_sheet.dart';
import 'package:matrix/matrix.dart';
import 'package:grid_frontend/utilities/lat_lng_validation.dart';

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
  ml.MapLibreMapController? _mapController;
  String? _styleJson;
  bool? _isDarkStyle;
  bool _styleLoaded = false;
  final List<ml.Line> _activeLines = [];
  final Map<String, Offset> _markerScreenPositions = {};
  int _projectionSeq = 0;
  LocationHistory? _locationHistory;
  Map<String, LocationHistory>? _groupHistories;
  double _sliderValue = 1.0;
  DateTime? _currentTime;
  Map<String, LatLng> _currentPositions = {};
  bool _isLoading = true;
  DateTime? _earliestTime;
  DateTime? _latestTime;
  bool _initialMapSetupDone = false;
  String? _selectedMemberId; // For group view, which member is selected
  bool _showAllMembers = false; // Toggle for showing all members vs single
  bool _mapReady = false;
  // First onCameraIdle after the platform view attaches. Until this fires the
  // native MLNMapView's frame may still be zero (the modal sheet animates up
  // from 0 height), and any setCamera call NaNs out through
  // constrainCameraAndZoomToBounds → SIGABRT. See maplibre_camera_facade.dart
  // for the full backstory.
  bool _nativeReady = false;
  _PendingHistoryMove? _pendingMove;
  Map<String, String> _userDisplayNames = {}; // Cache for display names
  late RoomLocationHistoryRepository _roomHistoryRepo;
  int _playbackSpeed = 1; // 1x / 2x / 4x playback multiplier
  static const List<int> _speedOptions = [1, 2, 4];
  Timer? _playbackTimer; // drives scrubber animation when playing
  bool _isPlaying = false;
  // One full 1x playback sweeps the whole range over this base duration.
  static const Duration _playbackBaseDuration = Duration(seconds: 12);
  static const Duration _playbackTick = Duration(milliseconds: 50);

  @override
  void initState() {
    super.initState();
    _roomHistoryRepo = RoomLocationHistoryRepository(DatabaseService());
    // Default to showing all members for group history
    _showAllMembers = widget.memberIds != null;
    _loadLocationHistory();
  }

  @override
  void dispose() {
    _playbackTimer?.cancel();
    _mapController = null;
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
            message: 'Past locations are no longer stored on this device.',
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

      if (!_mapReady) return;

      try {
        final points = _currentPositions.values.toList();
        if (points.length == 1) {
          _moveCamera(points.first, 12.0);
        } else if (points.length > 1) {
          final result = _calculateSmartZoom(points);
          _moveCamera(result.center, result.zoom);
        }
      } catch (e) {
        print('Error setting up initial map view: $e');
      }
    }
  }

  void _updateCurrentPositions() {
    final currentZoom = _mapController?.cameraPosition?.zoom ?? 12.0;
    if (_locationHistory != null && _currentTime != null) {
      // Single user
      final position = _getPositionAtTime(_locationHistory!, _currentTime!);
      if (position != null) {
        _currentPositions[widget.userId] = position;
        _moveCamera(position, currentZoom);
      }
    } else if (_groupHistories != null && _currentTime != null) {
      // Multiple users
      final newPositions = <String, LatLng>{};
      if (_showAllMembers) {
        _groupHistories!.forEach((userId, history) {
          final position = _getPositionAtTime(history, _currentTime!);
          if (position != null) {
            newPositions[userId] = position;
          }
        });
      } else if (_selectedMemberId != null && _groupHistories!.containsKey(_selectedMemberId!)) {
        final selectedHistory = _groupHistories![_selectedMemberId!]!;
        final userLatestTime = selectedHistory.points.isNotEmpty
            ? selectedHistory.points.last.timestamp
            : _currentTime!;
        final effectiveTime = _currentTime!.isAfter(userLatestTime)
            ? userLatestTime
            : _currentTime!;

        final position = _getPositionAtTime(selectedHistory, effectiveTime);
        if (position != null) {
          newPositions[_selectedMemberId!] = position;
          _moveCamera(position, currentZoom);
        }
      }
      _currentPositions = newPositions;
    }
    _redrawPaths();
    _refreshMarkerScreenPositions();
  }

  void _moveCamera(LatLng target, double zoom) {
    if (!isFiniteLatLng(target.latitude, target.longitude)) {
      debugPrint('[History] Skipping moveCamera — invalid coords: ${target.latitude},${target.longitude}');
      return;
    }
    final controller = _mapController;
    if (controller == null) return;
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    final z = (zoom.isNaN || zoom.isInfinite) ? 2.0 : zoom.clamp(0.0, 22.0);
    if (!_nativeReady) {
      _pendingMove = _PendingHistoryMove(target, z);
      return;
    }
    controller.moveCamera(ml.CameraUpdate.newCameraPosition(
      ml.CameraPosition(
        target: ml.LatLng(target.latitude, target.longitude),
        zoom: z,
      ),
    ));
  }

  void _onNativeReady() {
    if (_nativeReady) return;
    _nativeReady = true;
    final pending = _pendingMove;
    _pendingMove = null;
    if (pending != null) {
      scheduleMicrotask(() {
        if (mounted) _moveCamera(pending.target, pending.zoom);
      });
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
  
  List<({List<LatLng> points, Color color})> _buildPathSpecs() {
    final colorScheme = Theme.of(context).colorScheme;
    if (_locationHistory != null && _currentTime != null) {
      return [
        (
          points: _getPathForUser(_locationHistory!, _currentTime!),
          color: colorScheme.primary,
        ),
      ];
    }
    if (_showAllMembers && _groupHistories != null && _currentTime != null) {
      return _groupHistories!.entries
          .map((entry) => (
                points: _getPathForUser(entry.value, _currentTime!),
                color: _getUserColor(entry.key),
              ))
          .toList();
    }
    if (!_showAllMembers &&
        _selectedMemberId != null &&
        _groupHistories != null &&
        _groupHistories!.containsKey(_selectedMemberId!) &&
        _currentTime != null) {
      final selectedHistory = _groupHistories![_selectedMemberId!]!;
      final userLatestTime = selectedHistory.points.isNotEmpty
          ? selectedHistory.points.last.timestamp
          : _currentTime!;
      final effectiveTime = _currentTime!.isAfter(userLatestTime)
          ? userLatestTime
          : _currentTime!;
      return [
        (
          points: _getPathForUser(selectedHistory, effectiveTime),
          color: colorScheme.primary,
        ),
      ];
    }
    return const [];
  }

  Future<void> _redrawPaths() async {
    final controller = _mapController;
    if (controller == null || !_styleLoaded) return;
    try {
      if (_activeLines.isNotEmpty) {
        await controller.removeLines(List<ml.Line>.from(_activeLines));
        _activeLines.clear();
      }
      final specs = _buildPathSpecs();
      if (specs.isEmpty) return;
      final options = <ml.LineOptions>[
        for (final s in specs)
          if (s.points.isNotEmpty)
            ml.LineOptions(
              geometry: [
                for (final p in s.points)
                  if (isFiniteLatLng(p.latitude, p.longitude))
                    ml.LatLng(p.latitude, p.longitude),
              ],
              lineColor: _hex(s.color),
              lineWidth: 3.0,
              lineOpacity: 0.95,
              lineJoin: 'round',
            ),
      ];
      if (options.isEmpty) return;
      final lines = await controller.addLines(options);
      _activeLines.addAll(lines);
    } catch (e) {
      print('Error redrawing history paths: $e');
    }
  }

  String _hex(Color c) {
    final r = c.red.toRadixString(16).padLeft(2, '0');
    final g = c.green.toRadixString(16).padLeft(2, '0');
    final b = c.blue.toRadixString(16).padLeft(2, '0');
    return '#$r$g$b';
  }

  Future<void> _refreshMarkerScreenPositions() async {
    final controller = _mapController;
    if (controller == null || !mounted || _currentPositions.isEmpty) return;
    final keys = <String>[];
    final pts = <ml.LatLng>[];
    _currentPositions.forEach((k, v) {
      if (!isFiniteLatLng(v.latitude, v.longitude)) return;
      keys.add(k);
      pts.add(ml.LatLng(v.latitude, v.longitude));
    });
    final seq = ++_projectionSeq;
    try {
      final screen = await controller.toScreenLocationBatch(pts);
      if (!mounted || seq != _projectionSeq) return;
      _markerScreenPositions
        ..clear()
        ..addEntries([
          for (var i = 0; i < keys.length && i < screen.length; i++)
            MapEntry(keys[i], Offset(screen[i].x.toDouble(), screen[i].y.toDouble())),
        ]);
      setState(() {});
    } catch (_) {}
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

  /// Whether the loaded history spans more than one calendar day.
  bool get _spansMultipleDays {
    if (_earliestTime == null || _latestTime == null) return false;
    final a = _earliestTime!;
    final b = _latestTime!;
    return a.year != b.year || a.month != b.month || a.day != b.day;
  }

  /// Short absolute day context for [t] — "Today", "Yesterday", a weekday,
  /// or a calendar date. Used so multi-day history reads clearly.
  String _dayContextLabel(DateTime t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff > 1 && diff < 7) return DateFormat('EEE').format(t);
    return DateFormat('MMM d').format(t);
  }

  /// Absolute date + time for the current handle, e.g. "Today 3:40 PM".
  String _absoluteHandleLabel(DateTime t) =>
      '${_dayContextLabel(t)} ${DateFormat('h:mm a').format(t)}';

  /// Midnight day-boundary positions (0..1) across the loaded range, used to
  /// draw day tick marks along the scrubber track.
  List<double> _dayTickPositions() {
    if (_earliestTime == null || _latestTime == null) return const [];
    final total = _latestTime!.difference(_earliestTime!).inMilliseconds;
    if (total <= 0) return const [];
    final ticks = <double>[];
    var cursor = DateTime(
        _earliestTime!.year, _earliestTime!.month, _earliestTime!.day + 1);
    while (cursor.isBefore(_latestTime!)) {
      final frac = cursor.difference(_earliestTime!).inMilliseconds / total;
      if (frac > 0.02 && frac < 0.98) ticks.add(frac);
      cursor = DateTime(cursor.year, cursor.month, cursor.day + 1);
    }
    return ticks;
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
    final isDark = theme.brightness == Brightness.dark;
    if (_isDarkStyle != isDark) {
      _isDarkStyle = isDark;
      _styleJson = buildGridMapStyle(dark: isDark);
      if (_styleLoaded && _mapController != null) {
        unawaited(_mapController!.setStyle(_styleJson!));
        _styleLoaded = false;
      }
    }

    final isGroup = widget.memberIds != null;
    final headerTitle = isGroup
        ? '${widget.userName} · history'
        : '${widget.userName}’s history';

    final subtitleText = (_earliestTime != null && _latestTime != null)
        ? _formatHeaderSubtitle()
        : 'Loading';

    return GridSheetContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GridSheetHeader(
            title: headerTitle,
            subtitle: subtitleText,
            trailing: isGroup
                ? IconButton(
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      color: context.gridColors.danger,
                      size: 22,
                    ),
                    tooltip: 'Clear history',
                    onPressed: _showClearHistoryDialog,
                  )
                : null,
          ),
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: Column(
              children: [
          // Member strip — group mode. First tile = ALL.
          if (!_isLoading && _groupHistories != null && _groupHistories!.isNotEmpty)
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
                        _pausePlayback();
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
                            _pausePlayback();
                            setState(() {
                              _showAllMembers = false;
                              _selectedMemberId = memberId;
                              _updateSliderRange();
                              if (_currentPositions.containsKey(memberId)) {
                                _moveCamera(
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
                if (_isLoading)
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(
                          color: context.gridColors.mint,
                        ),
                        const SizedBox(height: 16),
                        GridMono(
                          'Loading history',
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
                else
                  ClipRRect(
                    borderRadius: BorderRadius.circular(GridTokens.rLg),
                    child: Stack(
                      children: [
                        ml.MapLibreMap(
                          styleString: _styleJson!,
                          initialCameraPosition: ml.CameraPosition(
                            target: ml.LatLng(
                              _currentPositions.isNotEmpty
                                  ? (_showAllMembers && _currentPositions.length > 1
                                      ? _calculateSmartZoom(_currentPositions.values.toList()).center.latitude
                                      : _currentPositions.values.first.latitude)
                                  : 37.7749,
                              _currentPositions.isNotEmpty
                                  ? (_showAllMembers && _currentPositions.length > 1
                                      ? _calculateSmartZoom(_currentPositions.values.toList()).center.longitude
                                      : _currentPositions.values.first.longitude)
                                  : -122.4194,
                            ),
                            zoom: _currentPositions.isNotEmpty && _showAllMembers
                                ? _calculateSmartZoom(_currentPositions.values.toList()).zoom
                                : 10.0,
                          ),
                          myLocationEnabled: false,
                          trackCameraPosition: true,
                          minMaxZoomPreference:
                              const ml.MinMaxZoomPreference(2.0, 16.0),
                          rotateGesturesEnabled: false,
                          tiltGesturesEnabled: false,
                          attributionButtonPosition:
                              ml.AttributionButtonPosition.bottomLeft,
                          onMapCreated: (controller) {
                            _mapController = controller;
                            controller.addListener(_onCameraTick);
                          },
                          onStyleLoadedCallback: () {
                            if (!mounted) return;
                            setState(() {
                              _styleLoaded = true;
                              _mapReady = true;
                            });
                            _redrawPaths();
                            if (!_initialMapSetupDone &&
                                _currentPositions.isNotEmpty) {
                              _setupInitialMapView();
                            }
                            _refreshMarkerScreenPositions();
                          },
                          onCameraIdle: () {
                            _onNativeReady();
                            _refreshMarkerScreenPositions();
                          },
                        ),
                        ..._currentPositions.entries.map((entry) {
                          final pos = _markerScreenPositions[entry.key];
                          if (pos == null) return const SizedBox.shrink();
                          return Positioned(
                            left: pos.dx - 25,
                            top: pos.dy - 25,
                            child: IgnorePointer(
                              child: SizedBox(
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
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),

              ],
            ),
            ),
          ),

          // Timeline scrubber — surface bg, top hairline
          if (!_isLoading &&
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
                      // Status row: play/pause + absolute handle time · speed pills
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(6, 4, 12, 4),
                              decoration: BoxDecoration(
                                color: context.gridColors.surface2,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: context.gridColors.hairline),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _PlayButton(
                                    playing: _isPlaying,
                                    onTap: _togglePlayback,
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: GridMono(
                                      _currentTime != null
                                          ? _absoluteHandleLabel(_currentTime!)
                                          : '--',
                                      color: context.gridColors.mint,
                                      size: 11,
                                      letterSpacing: 0.06,
                                      uppercase: false,
                                      weight: FontWeight.w600,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
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
                      // Slider — mint track + white thumb, day ticks for multi-day
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          if (_spansMultipleDays)
                            Positioned.fill(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: CustomPaint(
                                  painter: _DayTickPainter(
                                    positions: _dayTickPositions(),
                                    color: context.gridColors.text3,
                                  ),
                                ),
                              ),
                            ),
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
                                if (_isPlaying) _pausePlayback();
                                setState(() {
                                  _sliderValue = value;
                                  _updateTimeFromSlider();
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Absolute endpoints: day context + clock at each end
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _ScrubberEndLabel(
                            day: _earliestTime != null
                                ? _dayContextLabel(_earliestTime!)
                                : '',
                            time: _earliestTime != null
                                ? DateFormat('h:mm a').format(_earliestTime!)
                                : '--:--',
                            color: context.gridColors.text3,
                            align: CrossAxisAlignment.start,
                          ),
                          _ScrubberEndLabel(
                            day: _latestTime != null
                                ? _dayContextLabel(_latestTime!)
                                : '',
                            time: _latestTime != null
                                ? DateFormat('h:mm a').format(_latestTime!)
                                : '--:--',
                            color: context.gridColors.text3,
                            align: CrossAxisAlignment.end,
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

  void _togglePlayback() {
    if (_isPlaying) {
      _pausePlayback();
    } else {
      _startPlayback();
    }
  }

  void _startPlayback() {
    if (_earliestTime == null || _latestTime == null) return;
    if (_latestTime!.difference(_earliestTime!).inMilliseconds <= 0) return;
    // Restart from the beginning if parked at the end.
    if (_sliderValue >= 0.999) {
      _sliderValue = 0.0;
      _updateTimeFromSlider();
    }
    _playbackTimer?.cancel();
    setState(() => _isPlaying = true);
    _playbackTimer = Timer.periodic(_playbackTick, (_) => _advancePlayback());
  }

  void _pausePlayback() {
    _playbackTimer?.cancel();
    _playbackTimer = null;
    if (mounted) setState(() => _isPlaying = false);
  }

  void _advancePlayback() {
    if (!mounted) return;
    final step = (_playbackTick.inMilliseconds * _playbackSpeed) /
        _playbackBaseDuration.inMilliseconds;
    var next = _sliderValue + step;
    if (next >= 1.0) {
      next = 1.0;
      setState(() {
        _sliderValue = next;
        _updateTimeFromSlider();
      });
      _pausePlayback();
      return;
    }
    setState(() {
      _sliderValue = next;
      _updateTimeFromSlider();
    });
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
          _moveCamera(points.first, 6.0);
        } else if (points.length > 1) {
          final result = _calculateSmartZoom(points);
          _moveCamera(result.center, result.zoom);
        }
      } catch (e) {
        print('Error fitting all members in view: $e');
      }
    }
  }

  void _onCameraTick() {
    if (!mounted) return;
    _refreshMarkerScreenPositions();
  }

  // Smart zoom calculation matching main map logic
  ({LatLng center, double zoom}) _calculateSmartZoom(List<LatLng> points) {
    points = points.where((p) => isFiniteLatLng(p.latitude, p.longitude)).toList();
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

/// Circular play/pause toggle for scrubber playback.
class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.playing, required this.onTap});

  final bool playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: context.gridColors.mint,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(
            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: 17,
            color: context.gridColors.surface,
          ),
        ),
      ),
    );
  }
}

/// Two-line mono endpoint label: day context (e.g. "Mon") over a clock time.
class _ScrubberEndLabel extends StatelessWidget {
  const _ScrubberEndLabel({
    required this.day,
    required this.time,
    required this.color,
    required this.align,
  });

  final String day;
  final String time;
  final Color color;
  final CrossAxisAlignment align;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: align,
      children: [
        GridMono(
          day,
          color: color,
          size: 9.5,
          letterSpacing: 0.08,
        ),
        const SizedBox(height: 2),
        GridMono(
          time,
          color: color,
          size: 11,
          letterSpacing: 0.02,
          uppercase: false,
        ),
      ],
    );
  }
}

/// Paints faint vertical day-boundary ticks along the scrubber track.
class _DayTickPainter extends CustomPainter {
  _DayTickPainter({required this.positions, required this.color});

  final List<double> positions;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.5)
      ..strokeWidth = 1.0;
    final cy = size.height / 2;
    for (final p in positions) {
      final x = p * size.width;
      canvas.drawLine(Offset(x, cy - 5), Offset(x, cy + 5), paint);
    }
  }

  @override
  bool shouldRepaint(_DayTickPainter old) =>
      old.positions != positions || old.color != color;
}

class _PendingHistoryMove {
  _PendingHistoryMove(this.target, this.zoom);
  final LatLng target;
  final double zoom;
}
