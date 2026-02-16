import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:latlong2/latlong.dart';
import 'package:grid_frontend/blocs/map/map_bloc.dart';
import 'package:grid_frontend/blocs/map/map_event.dart';
import 'package:grid_frontend/blocs/map/map_state.dart';
import 'package:grid_frontend/models/user_location.dart';
import 'package:grid_frontend/repositories/location_repository.dart';
import 'package:grid_frontend/services/location_manager.dart';
import 'package:grid_frontend/services/database_service.dart';

class MockLocationManager extends Mock implements LocationManager {}
class MockLocationRepository extends Mock implements LocationRepository {}
class MockDatabaseService extends Mock implements DatabaseService {}

void main() {
  group('MapBloc', () {
    late MapBloc bloc;
    late MockLocationManager mockLocationManager;
    late MockLocationRepository mockLocationRepository;
    late MockDatabaseService mockDatabaseService;
    late StreamController<UserLocation> locationStreamController;

    setUp(() {
      mockLocationManager = MockLocationManager();
      mockLocationRepository = MockLocationRepository();
      mockDatabaseService = MockDatabaseService();
      locationStreamController = StreamController<UserLocation>.broadcast();

      when(() => mockLocationRepository.locationUpdates)
          .thenAnswer((_) => locationStreamController.stream);

      bloc = MapBloc(
        locationManager: mockLocationManager,
        locationRepository: mockLocationRepository,
        databaseService: mockDatabaseService,
      );
    });

    tearDown(() {
      bloc.close();
      locationStreamController.close();
    });

    test('initial state has isLoading true and empty locations', () {
      expect(bloc.state.isLoading, isTrue);
      expect(bloc.state.userLocations, isEmpty);
      expect(bloc.state.center, isNull);
      expect(bloc.state.error, isNull);
      expect(bloc.state.selectedUserId, isNull);
    });

    group('MapInitialize', () {
      blocTest<MapBloc, MapState>(
        'sets isLoading to false on initialize',
        build: () {
          when(() => mockLocationRepository.getAllLatestLocations())
              .thenAnswer((_) async => []);
          return bloc;
        },
        act: (bloc) => bloc.add(MapInitialize()),
        expect: () => [
          // MapInitialize emits isLoading: false, then MapLoadUserLocations also emits
          isA<MapState>().having((s) => s.isLoading, 'isLoading', false),
        ],
      );
    });

    group('RemoveUserLocation', () {
      blocTest<MapBloc, MapState>(
        'removes user location from state',
        seed: () => MapState(
          isLoading: false,
          userLocations: [
            UserLocation(userId: 'user1', latitude: 40.0, longitude: -74.0, timestamp: '2024-01-01T00:00:00Z', iv: 'test_iv'),
            UserLocation(userId: 'user2', latitude: 41.0, longitude: -75.0, timestamp: '2024-01-01T00:00:00Z', iv: 'test_iv'),
          ],
        ),
        build: () => bloc,
        act: (bloc) => bloc.add(const RemoveUserLocation('user1')),
        expect: () => [
          isA<MapState>().having(
            (s) => s.userLocations.length, 'locations count', 1,
          ).having(
            (s) => s.userLocations.first.userId, 'remaining user', 'user2',
          ),
        ],
      );

      test('removing nonexistent user keeps locations unchanged', () async {
        // Seed state via stream
        await Future.delayed(const Duration(milliseconds: 50));
        locationStreamController.add(UserLocation(
          userId: 'user1', latitude: 40.0, longitude: -74.0,
          timestamp: '2024-01-01T00:00:00Z', iv: 'test_iv',
        ));
        await Future.delayed(const Duration(milliseconds: 50));
        
        bloc.add(const RemoveUserLocation('nonexistent'));
        await Future.delayed(const Duration(milliseconds: 50));
        
        expect(bloc.state.userLocations.length, equals(1));
        expect(bloc.state.userLocations.first.userId, 'user1');
      });
    });

    group('MapLoadUserLocations', () {
      blocTest<MapBloc, MapState>(
        'loads all latest locations',
        build: () {
          when(() => mockLocationRepository.getAllLatestLocations())
              .thenAnswer((_) async => [
            UserLocation(userId: 'user1', latitude: 40.0, longitude: -74.0, timestamp: '2024-01-01T00:00:00Z', iv: 'iv1'),
            UserLocation(userId: 'user2', latitude: 41.0, longitude: -75.0, timestamp: '2024-01-01T00:00:00Z', iv: 'iv2'),
          ]);
          return bloc;
        },
        act: (bloc) => bloc.add(MapLoadUserLocations()),
        expect: () => [
          isA<MapState>().having(
            (s) => s.userLocations.length, 'locations count', 2,
          ).having((s) => s.isLoading, 'isLoading', false),
        ],
      );

      blocTest<MapBloc, MapState>(
        'deduplicates locations by userId',
        build: () {
          when(() => mockLocationRepository.getAllLatestLocations())
              .thenAnswer((_) async => [
            UserLocation(userId: 'user1', latitude: 40.0, longitude: -74.0, timestamp: '2024-01-01T00:00:00Z', iv: 'iv1'),
            UserLocation(userId: 'user1', latitude: 40.1, longitude: -74.1, timestamp: '2024-01-01T01:00:00Z', iv: 'iv2'),
          ]);
          return bloc;
        },
        act: (bloc) => bloc.add(MapLoadUserLocations()),
        expect: () => [
          isA<MapState>().having(
            (s) => s.userLocations.length, 'locations count', 1,
          ),
        ],
      );

      blocTest<MapBloc, MapState>(
        'emits error state when loading fails',
        build: () {
          when(() => mockLocationRepository.getAllLatestLocations())
              .thenThrow(Exception('DB error'));
          return bloc;
        },
        act: (bloc) => bloc.add(MapLoadUserLocations()),
        expect: () => [
          isA<MapState>().having(
            (s) => s.error, 'error', contains('Error loading user locations'),
          ),
        ],
      );

      blocTest<MapBloc, MapState>(
        'handles empty locations list',
        build: () {
          when(() => mockLocationRepository.getAllLatestLocations())
              .thenAnswer((_) async => []);
          return bloc;
        },
        act: (bloc) => bloc.add(MapLoadUserLocations()),
        expect: () => [
          isA<MapState>().having(
            (s) => s.userLocations, 'locations', isEmpty,
          ).having((s) => s.isLoading, 'isLoading', false),
        ],
      );
    });

    group('MapCenterOnUser', () {
      blocTest<MapBloc, MapState>(
        'centers on current user location',
        build: () {
          when(() => mockLocationManager.currentLatLng)
              .thenReturn(const LatLng(40.7128, -74.0060));
          return bloc;
        },
        act: (bloc) => bloc.add(MapCenterOnUser()),
        expect: () => [
          isA<MapState>().having(
            (s) => s.center, 'center', isNotNull,
          ),
        ],
      );

      blocTest<MapBloc, MapState>(
        'emits error when no user location available',
        build: () {
          when(() => mockLocationManager.currentLatLng).thenReturn(null);
          return bloc;
        },
        act: (bloc) => bloc.add(MapCenterOnUser()),
        expect: () => [
          isA<MapState>().having(
            (s) => s.error, 'error', 'No user location available',
          ),
        ],
      );
    });

    group('MapMoveToUser', () {
      blocTest<MapBloc, MapState>(
        'moves to user location and sets selectedUserId',
        build: () {
          when(() => mockLocationRepository.getLatestLocationFromHistory('user1'))
              .thenAnswer((_) async => UserLocation(
            userId: 'user1',
            latitude: 40.7128,
            longitude: -74.0060,
            timestamp: '2024-01-01T00:00:00Z',
            iv: 'test_iv',
          ));
          return bloc;
        },
        act: (bloc) => bloc.add(const MapMoveToUser('user1')),
        wait: const Duration(milliseconds: 200),
        expect: () => [
          // First emit clears center
          isA<MapState>().having((s) => s.center, 'center', isNull),
          // Second emit sets new center
          isA<MapState>().having(
            (s) => s.selectedUserId, 'selectedUserId', 'user1',
          ).having(
            (s) => s.center, 'center', isNotNull,
          ),
        ],
      );

      blocTest<MapBloc, MapState>(
        'emits error when user location not found',
        build: () {
          when(() => mockLocationRepository.getLatestLocationFromHistory('unknown'))
              .thenAnswer((_) async => null);
          return bloc;
        },
        act: (bloc) => bloc.add(const MapMoveToUser('unknown')),
        wait: const Duration(milliseconds: 200),
        expect: () => [
          isA<MapState>().having(
            (s) => s.error, 'error', contains('Location not available'),
          ),
        ],
      );
    });

    group('MapClearSelection', () {
      blocTest<MapBloc, MapState>(
        'clears selected user id',
        seed: () => const MapState(isLoading: false, selectedUserId: 'user1'),
        build: () => bloc,
        act: (bloc) => bloc.add(MapClearSelection()),
        expect: () => [
          isA<MapState>().having((s) => s.selectedUserId, 'selectedUserId', isNull),
        ],
      );
    });

    group('MapCenterOnLocation', () {
      blocTest<MapBloc, MapState>(
        'centers on specified location',
        build: () => bloc,
        act: (bloc) => bloc.add(const MapCenterOnLocation(LatLng(40.7128, -74.0060))),
        expect: () => [
          isA<MapState>().having(
            (s) => s.center?.latitude, 'lat', closeTo(40.7128, 0.001),
          ).having(
            (s) => s.center?.longitude, 'lng', closeTo(-74.006, 0.001),
          ),
        ],
      );

      blocTest<MapBloc, MapState>(
        'centers on location with custom zoom',
        build: () => bloc,
        act: (bloc) => bloc.add(const MapCenterOnLocation(LatLng(40.7128, -74.0060), zoom: 18.0)),
        expect: () => [
          isA<MapState>().having(
            (s) => s.zoom, 'zoom', 18.0,
          ),
        ],
      );
    });

    group('Location stream updates', () {
      test('updates state when location stream emits', () async {
        // Need to wait for bloc to subscribe
        await Future.delayed(const Duration(milliseconds: 50));

        locationStreamController.add(UserLocation(
          userId: 'user1',
          latitude: 40.0,
          longitude: -74.0,
          timestamp: '2024-01-01T00:00:00Z',
          iv: 'test_iv',
        ));

        await Future.delayed(const Duration(milliseconds: 50));
        expect(bloc.state.userLocations.length, equals(1));
        expect(bloc.state.userLocations.first.userId, equals('user1'));
      });

      test('replaces existing location for same user', () async {
        await Future.delayed(const Duration(milliseconds: 50));

        locationStreamController.add(UserLocation(
          userId: 'user1',
          latitude: 40.0,
          longitude: -74.0,
          timestamp: '2024-01-01T00:00:00Z',
          iv: 'iv1',
        ));
        await Future.delayed(const Duration(milliseconds: 50));

        locationStreamController.add(UserLocation(
          userId: 'user1',
          latitude: 41.0,
          longitude: -75.0,
          timestamp: '2024-01-01T01:00:00Z',
          iv: 'iv2',
        ));
        await Future.delayed(const Duration(milliseconds: 50));

        expect(bloc.state.userLocations.length, equals(1));
        expect(bloc.state.userLocations.first.latitude, equals(41.0));
      });

      test('keeps locations for different users', () async {
        await Future.delayed(const Duration(milliseconds: 50));

        locationStreamController.add(UserLocation(
          userId: 'user1',
          latitude: 40.0,
          longitude: -74.0,
          timestamp: '2024-01-01T00:00:00Z',
          iv: 'iv1',
        ));
        locationStreamController.add(UserLocation(
          userId: 'user2',
          latitude: 41.0,
          longitude: -75.0,
          timestamp: '2024-01-01T00:00:00Z',
          iv: 'iv2',
        ));
        await Future.delayed(const Duration(milliseconds: 50));

        expect(bloc.state.userLocations.length, equals(2));
      });

      test('deduplicates identical location updates', () async {
        await Future.delayed(const Duration(milliseconds: 50));

        final location = UserLocation(
          userId: 'user1',
          latitude: 40.0,
          longitude: -74.0,
          timestamp: '2024-01-01T00:00:00Z',
          iv: 'iv1',
        );

        locationStreamController.add(location);
        locationStreamController.add(location); // Same exact location
        await Future.delayed(const Duration(milliseconds: 50));

        expect(bloc.state.userLocations.length, equals(1));
      });
    });
  });

  group('MapState', () {
    test('default state', () {
      const state = MapState();
      expect(state.isLoading, isTrue);
      expect(state.center, isNull);
      expect(state.zoom, 16.0);
      expect(state.userLocations, isEmpty);
      expect(state.error, isNull);
      expect(state.moveCount, 0);
      expect(state.selectedUserId, isNull);
    });

    test('copyWith preserves values', () {
      final state = MapState(
        isLoading: false,
        center: const LatLng(40.0, -74.0),
        zoom: 18.0,
        userLocations: [
          UserLocation(userId: 'u1', latitude: 40.0, longitude: -74.0, timestamp: 't', iv: 'iv'),
        ],
        moveCount: 5,
        selectedUserId: 'u1',
      );

      final copied = state.copyWith();
      expect(copied.isLoading, isFalse);
      expect(copied.center?.latitude, 40.0);
      expect(copied.zoom, 18.0);
      expect(copied.userLocations.length, 1);
      expect(copied.moveCount, 5);
      expect(copied.selectedUserId, 'u1');
    });

    test('copyWith overrides values', () {
      const state = MapState(isLoading: true, zoom: 16.0);
      final newState = state.copyWith(isLoading: false, zoom: 20.0);
      expect(newState.isLoading, isFalse);
      expect(newState.zoom, 20.0);
    });

    test('copyWith clears error when not provided', () {
      const state = MapState(error: 'some error');
      final newState = state.copyWith(isLoading: false);
      expect(newState.error, isNull);
    });

    test('copyWith clearSelectedUserId', () {
      const state = MapState(selectedUserId: 'user1');
      final newState = state.copyWith(clearSelectedUserId: true);
      expect(newState.selectedUserId, isNull);
    });

    test('equality', () {
      const state1 = MapState(isLoading: false, zoom: 16.0);
      const state2 = MapState(isLoading: false, zoom: 16.0);
      expect(state1, equals(state2));
    });

    test('inequality', () {
      const state1 = MapState(isLoading: false);
      const state2 = MapState(isLoading: true);
      expect(state1, isNot(equals(state2)));
    });
  });
}
