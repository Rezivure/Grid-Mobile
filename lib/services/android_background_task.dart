import 'package:matrix/matrix.dart';
import 'package:grid_frontend/services/database_service.dart';
import 'package:grid_frontend/services/backwards_compatibility_service.dart';
import 'package:grid_frontend/repositories/location_repository.dart';
import 'package:grid_frontend/repositories/user_repository.dart';
import 'package:grid_frontend/repositories/room_repository.dart';
import 'package:grid_frontend/repositories/sharing_preferences_repository.dart';
import 'package:grid_frontend/repositories/user_keys_repository.dart';
import 'package:grid_frontend/services/user_service.dart';

// Static cache to reuse Matrix client across headless task invocations
// This prevents expensive reinitialization on every location update
Client? _cachedClient;
DatabaseService? _cachedDatabaseService;
DatabaseApi? _cachedDatabase;

@pragma('vm:entry-point')
void headlessDispatcher() async {
  print('[LibreLocation HeadlessDispatcher]: Initializing headless isolate');
  // Initialize the headless isolate if needed
}

@pragma('vm:entry-point')
void onHeadlessLocation(Map<String, dynamic> data) async {
  print('[LibreLocation HeadlessTask]: $data');
  
  // Parse the location data from libre_location
  final double? latitude = data['latitude']?.toDouble();
  final double? longitude = data['longitude']?.toDouble();
  final double? accuracy = data['accuracy']?.toDouble();
  final double? speed = data['speed']?.toDouble();
  final double? heading = data['heading']?.toDouble();
  final int? timestamp = data['timestamp']?.toInt();
  final bool? isMoving = data['isMoving'] as bool?;

  // Battery arrives either nested ('battery': {level 0-1, charging}) or as
  // top-level native keys ('batteryLevel' 0-100 int, 'isCharging').
  double? batteryLevel;
  bool? isCharging;
  final battery = data['battery'];
  if (battery is Map) {
    batteryLevel = (battery['level'] as num?)?.toDouble();
    isCharging = battery['charging'] as bool?;
  } else if (data['batteryLevel'] != null) {
    batteryLevel = (data['batteryLevel'] as num).toDouble() / 100.0;
    isCharging = data['isCharging'] as bool?;
  }

  if (latitude != null && longitude != null) {
    await processBackgroundLocation(
      latitude,
      longitude,
      accuracy ?? 0.0,
      DateTime.fromMillisecondsSinceEpoch(timestamp ?? DateTime.now().millisecondsSinceEpoch),
      isMoving ?? false,
      speed: speed,
      heading: heading,
      batteryLevel: batteryLevel,
      isCharging: isCharging,
    );
  } else {
    print('[HeadlessTask] ⚠️  Invalid location data received');
  }
}

Future<void> processBackgroundLocation(
  double latitude,
  double longitude,
  double accuracy,
  DateTime timestamp,
  bool isMoving, {
  double? speed,
  double? heading,
  double? batteryLevel,
  bool? isCharging,
}) async {
  try {
    // Reuse cached instances if available
    if (_cachedClient == null) {
      print('[HeadlessTask] 🔄 Initializing Matrix client (first run)');

      _cachedDatabaseService = DatabaseService();
      await _cachedDatabaseService!.initDatabase();

      _cachedDatabase = await BackwardsCompatibilityService.createMatrixDatabase();
      _cachedClient = Client(
        'Grid App',
        database: _cachedDatabase!,
      );
      await _cachedClient!.init();
      _cachedClient!.backgroundSync = false;

      print('[HeadlessTask] ✓ Matrix client initialized and cached');
    } else {
      print('[HeadlessTask] ⚡ Reusing cached Matrix client (fast path)');
    }

    // Initialize repositories (these are lightweight, not cached)
    final locationRepository = LocationRepository(_cachedDatabaseService!);
    final userRepository = UserRepository(_cachedDatabaseService!);
    final sharingPreferencesRepository = SharingPreferencesRepository(_cachedDatabaseService!);
    final userKeysRepository = UserKeysRepository(_cachedDatabaseService!);
    final roomRepository = RoomRepository(_cachedDatabaseService!);

    // Initialize services
    final userService = UserService(
      _cachedClient!,
      locationRepository,
      sharingPreferencesRepository,
    );

    // Process rooms and send updates
    List<Room> rooms = _cachedClient!.rooms;
    print("Grid: Found ${rooms.length} total rooms to process");

    final currentTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    for (Room room in rooms) {
      try {
        print("Grid: Processing room ${room.name} (${room.id})");

        if (!_shouldProcessRoom(room, currentTimestamp)) continue;

        var joinedMembers = room
            .getParticipants()
            .where((member) => member.membership == Membership.join)
            .toList();

        print("Grid: Room has ${joinedMembers.length} joined members");

        if (!joinedMembers.any((member) => member.id == _cachedClient?.userID)) {
          print("Grid: Skipping room ${room.id} - I am not a joined member");
          continue;
        }

        if (joinedMembers.length > 1) {
          if (!await _checkSharingWindow(room, joinedMembers, _cachedClient!, userService)) continue;

          await _sendLocationUpdate(
            room,
            latitude,
            longitude,
            accuracy,
            speed: speed,
            heading: heading,
            batteryLevel: batteryLevel,
            isCharging: isCharging,
          );
        } else {
          print("Grid: Skipping room ${room.id} - insufficient members");
        }
      } catch (e) {
        print('Error processing room ${room.name}: $e');
        continue;
      }
    }

    // Note: We DON'T dispose the client here since we're caching it for reuse!
    print('[HeadlessTask] ✓ Location processing complete');
  } catch (e) {
    print('[Background Task Error]: $e');

    // Clear cache on error so it reinitializes fresh next time
    print('[HeadlessTask] ⚠️  Error occurred, clearing cache for next run');
    _cachedClient = null;
    _cachedDatabase = null;
    _cachedDatabaseService = null;
  }
}

bool _shouldProcessRoom(Room room, int currentTimestamp) {
  if (!room.name.startsWith('Grid:')) {
    print("Grid: Skipping non-Grid room: ${room.name}");
    return false;
  }

  if (room.name.startsWith('Grid:Group:')) {
    final parts = room.name.split(':');
    if (parts.length < 3) return false;

    final expirationStr = parts[2];
    final expirationTimestamp = int.tryParse(expirationStr);

    print("Grid: Group room expiration: $expirationTimestamp, current: $currentTimestamp");

    if (expirationTimestamp != null &&
        expirationTimestamp != 0 &&
        expirationTimestamp < currentTimestamp) {
      print("Grid: Skipping expired group room");
      return false;
    }
  } else if (!room.name.startsWith('Grid:Direct:')) {
    print("Grid: Skipping unknown Grid room type: ${room.name}");
    return false;
  }

  return true;
}

Future<bool> _checkSharingWindow(Room room, List<User> joinedMembers, Client client, UserService userService) async {
  if (joinedMembers.length == 2 && room.name.startsWith('Grid:Direct:')) {
    var otherUsers = joinedMembers.where((member) => member.id != client.userID);
    var otherUser = otherUsers.first.id;

    final isSharing = await userService.isInSharingWindow(otherUser);
    if (!isSharing) {
      print("Grid: Skipping direct room ${room.id} - not in sharing window with $otherUser");
      return false;
    }
    print("In sharing window");
  }

  if (joinedMembers.length >= 2 && room.name.startsWith('Grid:Group:')) {
    final isSharing = await userService.isGroupInSharingWindow(room.id);
    if (!isSharing) {
      print("Grid: Skipping group room ${room.id} - not in sharing window");
      return false;
    }
    print("In sharing window");
  }

  return true;
}

Future<void> _sendLocationUpdate(
  Room room,
  double latitude,
  double longitude,
  double accuracy, {
  double? speed,
  double? heading,
  double? batteryLevel,
  bool? isCharging,
}) async {
  // Filter out low-accuracy locations to save battery and improve quality
  if (accuracy > 100) {
    print("Grid: ⚠️  Skipping low-accuracy location for ${room.name}: ${accuracy.toStringAsFixed(1)}m error");
    return;
  }

  // gridv 2 payload so background updates carry battery/speed too.
  final eventContent = <String, dynamic>{
    'msgtype': 'm.location',
    'body': 'Current location',
    'geo_uri': 'geo:$latitude,$longitude',
    'description': 'Current location',
    'timestamp': DateTime.now().toUtc().toIso8601String(),
    'gridv': 2,
    'accuracy': accuracy,
    if (speed != null) 'speed': speed,
    if (heading != null) 'heading': heading,
  };
  if (batteryLevel != null) {
    eventContent['battery'] = <String, dynamic>{
      'level': batteryLevel,
      if (isCharging != null) 'charging': isCharging,
    };
  }

  await room.sendEvent(eventContent);
  print("Grid: Location event sent to room ${room.id} / ${room.name} (accuracy: ${accuracy.toStringAsFixed(1)}m)");
}
