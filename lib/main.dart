import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart'; // Import dotenv
import 'package:grid_frontend/services/sync_manager.dart';
import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers/room_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/location_provider.dart';
import '/services/database_service.dart';
import 'services/location_tracking_service.dart';
import 'services/location_broadcast_service.dart';
import 'screens/onboarding/splash_screen.dart';
import 'screens/onboarding/welcome_screen.dart';
import 'screens/onboarding/server_select_screen.dart';
import 'screens/onboarding/login_screen.dart';
import 'screens/onboarding/signup_screen.dart';
import 'screens/map/map_tab.dart';
import 'package:grid_frontend/providers/user_location_provider.dart';
import 'package:grid_frontend/providers/selected_user_provider.dart';
import 'package:grid_frontend/providers/selected_subscreen_provider.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load .env file
  await dotenv.load(fileName: ".env");

  final databaseService = DatabaseService();
  await databaseService.initDatabase();

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

  final prefs = await SharedPreferences.getInstance();
  String? token = prefs.getString('token');

  if (token != null && token.isNotEmpty) {
    try {
      // Attempt to restore session using the token
      client.accessToken = token;
      await client.sync();
    } catch (e) {
      print('Error restoring session with token: $e');
    }
  }

  final syncManager = SyncManager(client);

  runApp(GridApp(client: client, databaseService: databaseService, syncManager: syncManager));
}

class GridApp extends StatelessWidget {
  final Client client;
  final DatabaseService databaseService;
  final SyncManager syncManager;

  const GridApp({required this.client, required this.databaseService, required this.syncManager, Key? key})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<Client>.value(value: client),
        Provider<DatabaseService>.value(value: databaseService),
        ChangeNotifierProvider(create: (_) => syncManager..startSync()),
        ChangeNotifierProvider(create: (_) => SelectedUserProvider()),
        ChangeNotifierProvider(create: (_) => SelectedSubscreenProvider()),
        ChangeNotifierProvider(create: (_) => UserLocationProvider()),
        ChangeNotifierProvider(create: (context) => AuthProvider(client, databaseService)),
        ChangeNotifierProvider(create: (context) => RoomProvider(client, databaseService)),
        ChangeNotifierProvider(create: (context) => LocationProvider()),
        Provider(create: (context) => LocationBroadcastService(
          Provider.of<LocationProvider>(context, listen: false),
          Provider.of<RoomProvider>(context, listen: false),
        )),
        Provider(create: (context) => LocationTrackingService(
          Provider.of<DatabaseService>(context, listen: false),
          Provider.of<RoomProvider>(context, listen: false),
            Provider.of<LocationProvider>(context, listen: false)
        )),
      ],
      child: MaterialApp(
        title: 'Grid App',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Color(0xFF00DBA4), // Caribbean Green
            primary: Color(0xFF00DBA4), // Caribbean Green
            secondary: Color(0xFF267373), // Oracle
            tertiary: Color(0xFFDCF8C6), // Light green (used for backgrounds)
            background: Colors.white, // Background color
            surface: Colors.white, // Surface color
            onPrimary: Colors.white, // Text/icon color on primary
            onSecondary: Colors.black, // Text/icon color on secondary
            onBackground: Colors.black, // Text color on background
            onSurface: Colors.black, // Text color on surface
            brightness: Brightness.light, // Light mode
          ),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Color(0xFF00DBA4), // Caribbean Green
            primary: Color(0xFF00DBA4), // Caribbean Green
            secondary: Color(0xFF267373), // Oracle
            tertiary: Color(0xFF3E4E50), // Darker shade for dark mode backgrounds
            background: Colors.black, // Background color
            surface: Colors.black, // Surface color
            onPrimary: Colors.black, // Text/icon color on primary
            onSecondary: Colors.white, // Text/icon color on secondary
            onBackground: Colors.white, // Text color on background
            onSurface: Colors.white, // Text color on surface
            brightness: Brightness.dark, // Dark mode
          ),
        ),
        themeMode: ThemeMode.system, // Automatically switch between light and dark mode based on system settings
        home: client.isLogged() ? MapTab() : SplashScreen(),
        routes: {
          '/welcome': (context) => WelcomeScreen(),
          '/server_select': (context) => ServerSelectScreen(),
          '/login': (context) => LoginScreen(),
          '/signup': (context) => SignUpScreen(),
          '/main': (context) => MapTab(),
        },
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  @override
  void initState() {
    super.initState();
    final currentUserId = Provider.of<AuthProvider>(context, listen: false).userId ?? 'default-user-id';

    // Initialize LocationBroadcastService and LocationTrackingService upon login
    final locationBroadcastService = Provider.of<LocationBroadcastService>(context, listen: false);
    final locationTrackingService = Provider.of<LocationTrackingService>(context, listen: false);

    locationBroadcastService.startBroadcastingLocation();
    locationTrackingService.startService();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: MapTab(),
    );
  }
}