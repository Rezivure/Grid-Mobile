import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';

import 'styles/tokens.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:matrix/matrix.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;

import 'package:grid_frontend/services/database_service.dart';
import 'package:grid_frontend/services/backwards_compatibility_service.dart';
import 'package:grid_frontend/services/android_background_task.dart';
import 'package:grid_frontend/repositories/location_repository.dart';
import 'package:grid_frontend/repositories/location_history_repository.dart';
import 'package:grid_frontend/repositories/room_location_history_repository.dart';
import 'package:grid_frontend/repositories/user_keys_repository.dart';
import 'package:grid_frontend/repositories/user_repository.dart';
import 'package:grid_frontend/repositories/room_repository.dart';
import 'package:grid_frontend/repositories/sharing_preferences_repository.dart';
import 'package:grid_frontend/repositories/map_icon_repository.dart';
import 'package:grid_frontend/services/map_icon_sync_service.dart';

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
import 'widgets/app_initializer.dart';
import 'screens/onboarding/login_screen.dart';
import 'screens/onboarding/signup_screen.dart';
import 'screens/map/map_tab.dart';

import 'package:grid_frontend/blocs/map/map_bloc.dart';
import 'package:grid_frontend/blocs/contacts/contacts_bloc.dart';
import 'package:grid_frontend/blocs/groups/groups_bloc.dart';
import 'package:grid_frontend/blocs/avatar/avatar_bloc.dart';
import 'package:grid_frontend/blocs/map_icons/map_icons_bloc.dart';
import 'package:grid_frontend/blocs/invitations/invitations_bloc.dart';
import 'package:grid_frontend/blocs/invitations/invitations_event.dart';
import 'package:grid_frontend/repositories/invitations_repository.dart';

import 'package:grid_frontend/widgets/version_wrapper.dart';
import 'package:grid_frontend/widgets/migration_modal.dart';
import 'package:libre_location/libre_location.dart';
import 'package:grid_frontend/services/debug_log_service.dart';
import 'package:grid_frontend/services/push_notification_service.dart';
import 'package:grid_frontend/services/push/notification_channels.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';




void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  LibreLocation.registerHeadlessDispatcher(headlessDispatcher, onHeadlessLocation);

  // Initialize Firebase (for push notifications)
  try {
    await Firebase.initializeApp();
    debugPrint('[Push] Firebase initialized');
  } catch (e) {
    debugPrint('[Push] Firebase init failed (ok if no config): $e');
  }

  // Load .env file
  await dotenv.load(fileName: ".env");

  // Initialize DatabaseService
  final databaseService = DatabaseService();
  await databaseService.initDatabase();

  await vod.init();

  // Initialize Matrix Client with backwards compatible database
  final database = await BackwardsCompatibilityService.createMatrixDatabase();
  final client = Client(
    'Grid App',
    database: database,
    nativeImplementations: NativeImplementationsIsolate(
      compute,
      vodozemacInit: () => vod.init(),
    ),
    // Share encryption keys with all devices, not just cross-verified ones
    // This ensures location sharing works without requiring device verification
    shareKeysWith: ShareKeysWith.all,
  );
  await client.init();

  // Initialize debug logging service
  await DebugLogService.instance.init();

  // Attempt to restore session
  // TODO: this code chunk may do nothing actually
  final prefs = await SharedPreferences.getInstance();
  String? token = prefs.getString('token');

  if (token != null && token.isNotEmpty) {
    try {
      client.accessToken = token;

      // Register push notifications on session restore
      if (client.isLogged()) {
        final pushService = PushNotificationService(client: client);
        await pushService.register();
      }
    } catch (e) {
      print('Error restoring session with token: $e');
    }
  }

  // Initialize notification channels (Android)
  await NotificationChannels.createAll();


  // Initialize repositories
  final userRepository = UserRepository(databaseService);
  final roomRepository = RoomRepository(databaseService);
  final sharingPreferencesRepository = SharingPreferencesRepository(databaseService);
  final locationRepository = LocationRepository(databaseService);
  final locationHistoryRepository = LocationHistoryRepository(databaseService);
  final roomLocationHistoryRepository = RoomLocationHistoryRepository(databaseService);
  final userKeysRepository = UserKeysRepository(databaseService);
  final locationManager = LocationManager();
  // Initialize services
  final userService = UserService(client, locationRepository, sharingPreferencesRepository);
  final roomService = RoomService(
    client, 
    userService, 
    userRepository, 
    userKeysRepository, 
    roomRepository, 
    locationRepository, 
    locationHistoryRepository, 
    sharingPreferencesRepository, 
    locationManager,
    roomLocationHistoryRepository: roomLocationHistoryRepository,
  );

  final messageParser = MessageParser();

  runApp(
    MultiProvider(
      providers: [
        Provider<Client>.value(value: client),
        Provider<DatabaseService>.value(value: databaseService),
        Provider<LocationRepository>.value(value: locationRepository),
        Provider<LocationHistoryRepository>.value(value: locationHistoryRepository),
        Provider<UserKeysRepository>.value(value: userKeysRepository),
        Provider<UserService>.value(value: userService),
        Provider<UserRepository>.value(value: userRepository),
        Provider<RoomRepository>.value(value: roomRepository),
        Provider<SharingPreferencesRepository>.value(value: sharingPreferencesRepository),

        ChangeNotifierProvider(create: (_) => SelectedUserProvider()),
        ChangeNotifierProvider(create: (_) => SelectedSubscreenProvider()),
        ChangeNotifierProvider(
          create: (context) => UserLocationProvider(context.read<LocationRepository>(), context.read<UserRepository>()),
        ),
        ChangeNotifierProvider(create: (context) => AuthProvider(client, databaseService)),
        ChangeNotifierProvider(
          create: (context) => UserLocationProvider(context.read<LocationRepository>(), context.read<UserRepository>()),
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
              locationHistoryRepository,
              sharingPreferencesRepository,
              locationManager,
              roomLocationHistoryRepository: roomLocationHistoryRepository,
            );
          },
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<AvatarBloc>(
            create: (context) => AvatarBloc(client: client),
          ),
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
              locationRepository: context.read<LocationRepository>(),
              userLocationProvider: context.read<UserLocationProvider>(),
              sharingPreferencesRepository: context.read<SharingPreferencesRepository>(),
            ),
          ),
          BlocProvider<GroupsBloc>(
            create: (context) => GroupsBloc(
              roomService: context.read<RoomService>(),
              roomRepository: context.read<RoomRepository>(),
              userRepository: context.read<UserRepository>(),
              mapBloc: context.read<MapBloc>(),
              locationRepository: context.read<LocationRepository>(),
              userLocationProvider: context.read<UserLocationProvider>(),
            ),
          ),
          BlocProvider<MapIconsBloc>(
            create: (context) => MapIconsBloc(
              mapIconRepository: MapIconRepository(databaseService),
            ),
          ),
          BlocProvider<InvitationsBloc>(
            create: (context) => InvitationsBloc(
              repository: InvitationsRepository(),
            )..add(LoadInvitations()),
          ),
          ChangeNotifierProxyProvider5<AvatarBloc, MapBloc, ContactsBloc, GroupsBloc, InvitationsBloc, SyncManager>(
            create: (context) {
              // Create MapIconSyncService
              final mapIconRepository = MapIconRepository(databaseService);
              final mapIconSyncService = MapIconSyncService(
                client: client,
                mapIconRepository: mapIconRepository,
                mapIconsBloc: context.read<MapIconsBloc>(),
              );
              
              final messageProcessor = MessageProcessor(
                locationRepository,
                locationHistoryRepository,
                messageParser, 
                client,
                avatarBloc: context.read<AvatarBloc>(),
                mapIconSyncService: mapIconSyncService,
                roomLocationHistoryRepository: roomLocationHistoryRepository,
              );
              return SyncManager(
                client,
                messageProcessor,
                roomRepository,
                userRepository,
                roomService,
                context.read<MapBloc>(),
                context.read<ContactsBloc>(),
                locationRepository,
                context.read<GroupsBloc>(),
                context.read<UserLocationProvider>(),
                context.read<SharingPreferencesRepository>(),
                context.read<InvitationsBloc>(),
                mapIconSyncService: mapIconSyncService,
                locationManager: context.read<LocationManager>(),
              )..startSync();
            },
            update: (context, avatarBloc, mapBloc, contactsBloc, groupsBloc, invitationsBloc, previous) {
              if (previous != null) return previous;
              
              // Create MapIconSyncService
              final mapIconRepository = MapIconRepository(databaseService);
              final mapIconSyncService = MapIconSyncService(
                client: client,
                mapIconRepository: mapIconRepository,
                mapIconsBloc: context.read<MapIconsBloc>(),
              );
              
              final messageProcessor = MessageProcessor(
                locationRepository,
                locationHistoryRepository,
                messageParser, 
                client,
                avatarBloc: avatarBloc,
                mapIconSyncService: mapIconSyncService,
                roomLocationHistoryRepository: roomLocationHistoryRepository,
              );
              return SyncManager(
                client,
                messageProcessor,
                roomRepository,
                userRepository,
                roomService,
                mapBloc,
                contactsBloc,
                locationRepository,
                groupsBloc,
                context.read<UserLocationProvider>(),
                sharingPreferencesRepository,
                invitationsBloc,
                mapIconSyncService: mapIconSyncService,
                locationManager: context.read<LocationManager>(),
              )..startSync();
            },
          ),
        ],
        child: MaterialApp(
          title: 'Grid App',
          theme: _buildTheme(GridTokens.lightScheme()),
          darkTheme: _buildTheme(GridTokens.darkScheme()),
          themeMode: ThemeMode.system,
          home: VersionWrapper(
            client: client,
            child: AppInitializer(client: client),
          ),
          routes: {
            '/welcome': (context) => WelcomeScreen(),
            '/server_select': (context) => ServerSelectScreen(),
            '/login': (context) => LoginScreen(),
            '/signup': (context) => SignUpScreen(),
            '/main': (context) => const MapTab(),
            '/migration': (context) => Scaffold(
              body: Center(
                child: MigrationModal(),
              ),
            ),
          },
        ),
      ),
    ),
  );
}

/// Build the app theme from a Grid-tokenized ColorScheme.
///
/// - Geist for UI body text, Geist Mono for status/coords/timestamps
///   (apply mono ad-hoc per widget via `GoogleFonts.geistMono`).
/// - Surfaces, shadows and rounded radii match the design tokens.
ThemeData _buildTheme(ColorScheme scheme) {
  final base = scheme.brightness == Brightness.dark
      ? ThemeData.dark(useMaterial3: true)
      : ThemeData.light(useMaterial3: true);

  final textTheme = GoogleFonts.getTextTheme('Geist', base.textTheme).apply(
    bodyColor: scheme.onSurface,
    displayColor: scheme.onSurface,
  );

  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    canvasColor: scheme.surface,
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.getFont('Geist',
        color: scheme.onSurface,
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.015,
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceVariant,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GridTokens.rLg),
        side: BorderSide(color: scheme.outlineVariant, width: 1),
      ),
    ),
    dividerColor: scheme.outlineVariant,
    iconTheme: IconThemeData(color: scheme.onSurface),
    primaryIconTheme: IconThemeData(color: scheme.onPrimary),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        textStyle: GoogleFonts.getFont('Geist',
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.onSurface,
        minimumSize: const Size.fromHeight(52),
        side: BorderSide(color: scheme.outline, width: 1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        textStyle: GoogleFonts.getFont('Geist',
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: scheme.primary,
        textStyle: GoogleFonts.getFont('Geist',
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceVariant,
      hintStyle: GoogleFonts.getFont('Geist',color: GridTokens.text3, fontSize: 15),
      labelStyle: GoogleFonts.getFont('Geist',color: GridTokens.text2, fontSize: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(GridTokens.rMd),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(GridTokens.rMd),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(GridTokens.rMd),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: GoogleFonts.getFont('Geist',color: scheme.onInverseSurface),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GridTokens.rMd),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(GridTokens.r2Xl),
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GridTokens.rXl),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.white
            : scheme.onSurface.withOpacity(0.5),
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? scheme.primary
            : scheme.surfaceContainerHighest,
      ),
    ),
  );
}
