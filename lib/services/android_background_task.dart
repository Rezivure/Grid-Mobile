import 'package:flutter_background_geolocation/flutter_background_geolocation.dart' as bg;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:matrix/matrix.dart';
import 'package:grid_frontend/services/database_service.dart';
import 'package:grid_frontend/repositories/location_repository.dart';
import 'package:grid_frontend/repositories/user_repository.dart';
import 'package:grid_frontend/repositories/room_repository.dart';
import 'package:grid_frontend/repositories/sharing_preferences_repository.dart';
import 'package:grid_frontend/repositories/user_keys_repository.dart';
import 'package:grid_frontend/services/user_service.dart';

@pragma('vm:entry-point')
void headlessTask(bg.HeadlessEvent headlessEvent) async {
  print('[BackgroundGeolocation HeadlessTask]: $headlessEvent');

  switch (headlessEvent.name) {
    case bg.Event.LOCATION:
      if (headlessEvent.event is bg.Location) {
        bg.Location location = headlessEvent.event as bg.Location;
        print('- Location: $location');
        await processBackgroundLocation(location);
      }
      break;

    case bg.Event.HEARTBEAT:
      if (headlessEvent.event is bg.HeartbeatEvent) {
        final bg.HeartbeatEvent hbEvent = headlessEvent.event as bg.HeartbeatEvent;
        final bg.Location? location = hbEvent.location;

        print('- Heartbeat location: $location');
        await processBackgroundLocation(location!);
      }
      break;



  }
}

Future<void> processBackgroundLocation(bg.Location location) async {
  Client? client;
  HiveCollectionsDatabase? db;

  try {
    // Initialize database
    final databaseService = DatabaseService();
    await databaseService.initDatabase();

    // Initialize Matrix client
    client = Client(
      'Grid App',
      databaseBuilder: (_) async {
        final dir = await getApplicationSupportDirectory();
        db = HiveCollectionsDatabase('grid_app', dir.path);
        await db?.open();
        return db!;
      },
    );
    await client.init();
    client.backgroundSync = false;


    // Initialize repositories
    final locationRepository = LocationRepository(databaseService);
    final userRepository = UserRepository(databaseService);
    final sharingPreferencesRepository = SharingPreferencesRepository(databaseService);
    final userKeysRepository = UserKeysRepository(databaseService);
    final roomRepository = RoomRepository(databaseService);

    // Initialize services
    final userService = UserService(
      client,
      locationRepository,
      sharingPreferencesRepository,
    );

    // Process rooms and send updates
    List<Room> rooms = client.rooms;
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

        if (!joinedMembers.any((member) => member.id == client?.userID)) {
          print("Grid: Skipping room ${room.id} - I am not a joined member");
          continue;
        }

        if (joinedMembers.length > 1) {
          if (!await _checkSharingWindow(room, joinedMembers, client, userService)) continue;

          await _sendLocationUpdate(room, location);
        } else {
          print("Grid: Skipping room ${room.id} - insufficient members");
        }
      } catch (e) {
        print('Error processing room ${room.name}: $e');
        continue;
      }
    }

    // Important: Wait for any pending operations to complete
    await client?.dispose(closeDatabase: true);

  } catch (e) {
    print('[Background Task Error]: $e');
  } finally {
    try {
      // Close the database after all operations are done
      await client?.dispose();
    } catch (e) {
      print('Error during cleanup: $e');
    }
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

Future<void> _sendLocationUpdate(Room room, bg.Location location) async {
  final eventContent = {
    'msgtype': 'm.location',
    'body': 'Current location',
    'geo_uri': 'geo:${location.coords.latitude},${location.coords.longitude}',
    'description': 'Current location',
    'timestamp': DateTime.now().toUtc().toIso8601String(),
  };

  await room.sendEvent(eventContent);
  print("Grid: Location event sent to room ${room.id} / ${room.name}");
}