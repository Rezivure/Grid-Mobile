import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:matrix/matrix.dart';

import 'package:grid_frontend/services/database_service.dart';
import 'package:grid_frontend/repositories/location_repository.dart';
import 'package:grid_frontend/repositories/user_keys_repository.dart';
import 'package:grid_frontend/repositories/user_repository.dart';
import 'package:grid_frontend/repositories/room_repository.dart';
import 'package:grid_frontend/repositories/sharing_preferences_repository.dart';

import 'package:grid_frontend/utilities/message_parser.dart';
import 'package:grid_frontend/services/message_processor.dart';
import 'package:grid_frontend/services/sync_manager.dart';
import 'package:grid_frontend/providers/auth_provider.dart';
import 'package:grid_frontend/services/location_manager.dart';
import 'package:grid_frontend/providers/user_location_provider.dart';
import 'package:grid_frontend/providers/selected_user_provider.dart';
import 'package:grid_frontend/providers/selected_subscreen_provider.dart';
import 'package:grid_frontend/services/user_service.dart';
import 'package:grid_frontend/services/room_service.dart';

import 'screens/onboarding/splash_screen.dart';
import 'screens/onboarding/welcome_screen.dart';
import 'screens/onboarding/server_select_screen.dart';
import 'screens/onboarding/login_screen.dart';
import 'screens/onboarding/signup_screen.dart';
import 'screens/map/map_tab.dart';

import 'package:grid_frontend/blocs/map/map_bloc.dart';
import 'package:grid_frontend/blocs/contacts/contacts_bloc.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load .env file
  await dotenv.load(fileName: ".env");

  // Initialize DatabaseService
  final databaseService = DatabaseService();
  await databaseService.initDatabase();

  // Initialize Matrix Client
  final client = Client(
    'Grid App',
    databaseBuilder: (_) async {
      final dir = await getApplicationSupportDirectory();
      final db = HiveCollectionsDatabase('grid_app', dir.path);
      await db.open();
      return db;
    },
  );
  await client.init();

  // Attempt to restore session
  final prefs = await SharedPreferences.getInstance();
  String? token = prefs.getString('token');

  if (token != null && token.isNotEmpty) {
    try {
      client.accessToken = token;
      await client.sync();
    } catch (e) {
      print('Error restoring session with token: $e');
    }
  }

  // Initialize repositories
  final userRepository = UserRepository(databaseService);
  final roomRepository = RoomRepository(databaseService);
  final sharingPreferencesRepository = SharingPreferencesRepository(databaseService);
  final locationRepository = LocationRepository(databaseService);
  final userKeysRepository = UserKeysRepository(databaseService);
  final locationManager = LocationManager();
  // Initialize services
  final userService = UserService(client, locationRepository);
  final roomService = RoomService(client, userService, userRepository, userKeysRepository, roomRepository, locationRepository, sharingPreferencesRepository, locationManager);

  final messageParser = MessageParser();
  final messageProcessor = MessageProcessor(locationRepository, messageParser, client);

  runApp(
    MultiProvider(
      providers: [
        Provider<Client>.value(value: client),
        Provider<DatabaseService>.value(value: databaseService),
        Provider<LocationRepository>.value(value: locationRepository),
        Provider<UserKeysRepository>.value(value: userKeysRepository),
        Provider<UserService>.value(value: userService),
        Provider<UserRepository>.value(value: userRepository),
        Provider<RoomRepository>.value(value: roomRepository),
        Provider<SharingPreferencesRepository>.value(value: sharingPreferencesRepository),

        ChangeNotifierProvider(create: (_) => SelectedUserProvider()),
        ChangeNotifierProvider(create: (_) => SelectedSubscreenProvider()),
        ChangeNotifierProvider(
          create: (context) => UserLocationProvider(context.read<LocationRepository>()),
        ),
        ChangeNotifierProvider(create: (context) => AuthProvider(client, databaseService)),
        ChangeNotifierProvider(
          create: (context) => UserLocationProvider(context.read<LocationRepository>()),
        ),

        // Provide the LocationManager
        ChangeNotifierProvider<LocationManager>(
          create: (context) => LocationManager(),
        ),

        // Provide the RoomService
        ProxyProvider<LocationManager, RoomService>(
          update: (context, locationManager, previousRoomService) {
            return previousRoomService ?? RoomService(
              client,
              context.read<UserService>(),
              userRepository,
              userKeysRepository,
              roomRepository,
              locationRepository,
              sharingPreferencesRepository,
              locationManager,
            );
          },
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<MapBloc>(
            create: (context) => MapBloc(
              locationManager: context.read<LocationManager>(),
              locationRepository: context.read<LocationRepository>(),
              databaseService: context.read<DatabaseService>(),
            ),
          ),
          BlocProvider<ContactsBloc>(
            create: (context) => ContactsBloc(
              roomService: context.read<RoomService>(),
              userRepository: context.read<UserRepository>(),
              mapBloc: context.read<MapBloc>(),
            ),
          ),
          ChangeNotifierProxyProvider2<MapBloc, ContactsBloc, SyncManager>(
            create: (context) => SyncManager(
              client,
              messageProcessor,
              roomRepository,
              userRepository,
              roomService,
              context.read<MapBloc>(),
              context.read<ContactsBloc>(),
              locationRepository,
            )..startSync(),
            update: (context, mapBloc, contactsBloc, previous) => previous ?? SyncManager(
              client,
              messageProcessor,
              roomRepository,
              userRepository,
              roomService,
              mapBloc,
              contactsBloc,
              locationRepository,
            )..startSync(),
          ),
        ],
        child: MaterialApp(
          title: 'Grid App',
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF00DBA4),
              primary: const Color(0xFF00DBA4),
              secondary: const Color(0xFF267373),
              tertiary: const Color(0xFFDCF8C6),
              background: Colors.white,
              surface: Colors.white,
              onPrimary: Colors.white,
              onSecondary: Colors.black,
              onBackground: Colors.black,
              onSurface: Colors.black,
              brightness: Brightness.light,
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF00DBA4),
              primary: const Color(0xFF00DBA4),
              secondary: const Color(0xFF267373),
              tertiary: const Color(0xFF3E4E50),
              background: Colors.black,
              surface: Colors.black,
              onPrimary: Colors.black,
              onSecondary: Colors.white,
              onBackground: Colors.white,
              onSurface: Colors.white,
              brightness: Brightness.dark,
            ),
          ),
          themeMode: ThemeMode.system,
          home: client.isLogged() ? const MapTab() : SplashScreen(),
          routes: {
            '/welcome': (context) => WelcomeScreen(),
            '/server_select': (context) => ServerSelectScreen(),
            '/login': (context) => LoginScreen(),
            '/signup': (context) => SignUpScreen(),
            '/main': (context) => const MapTab(),
          },
        ),
      ),
    ),
  );
}
