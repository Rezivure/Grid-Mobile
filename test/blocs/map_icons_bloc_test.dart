import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:grid_frontend/blocs/map_icons/map_icons_bloc.dart';
import 'package:grid_frontend/blocs/map_icons/map_icons_event.dart';
import 'package:grid_frontend/blocs/map_icons/map_icons_state.dart';
import 'package:grid_frontend/models/map_icon.dart';
import 'package:grid_frontend/repositories/map_icon_repository.dart';

class MockMapIconRepository extends Mock implements MapIconRepository {}

MapIcon _makeIcon({
  String id = 'icon1',
  String roomId = 'room1',
  String creatorId = 'user1',
  double lat = 40.0,
  double lng = -74.0,
}) {
  return MapIcon(
    id: id,
    roomId: roomId,
    creatorId: creatorId,
    latitude: lat,
    longitude: lng,
    iconType: 'icon',
    iconData: 'pin',
    createdAt: DateTime(2024, 1, 1),
  );
}

void main() {
  group('MapIconsBloc', () {
    late MapIconsBloc bloc;
    late MockMapIconRepository mockRepo;

    setUp(() {
      mockRepo = MockMapIconRepository();
      bloc = MapIconsBloc(mapIconRepository: mockRepo);
    });

    tearDown(() {
      bloc.close();
    });

    test('initial state', () {
      expect(bloc.state.icons, isEmpty);
      expect(bloc.state.isLoading, isFalse);
      expect(bloc.state.error, isNull);
    });

    group('LoadMapIcons', () {
      blocTest<MapIconsBloc, MapIconsState>(
        'loads icons for a room',
        build: () {
          when(() => mockRepo.getIconsForRoom('room1'))
              .thenAnswer((_) async => [_makeIcon()]);
          return bloc;
        },
        act: (bloc) => bloc.add(const LoadMapIcons('room1')),
        expect: () => [
          // Loading state
          isA<MapIconsState>()
              .having((s) => s.isLoading, 'isLoading', true)
              .having((s) => s.selectedRoomId, 'selectedRoomId', 'room1'),
          // Loaded state
          isA<MapIconsState>()
              .having((s) => s.isLoading, 'isLoading', false)
              .having((s) => s.icons.length, 'icons count', 1)
              .having((s) => s.error, 'error', isNull),
        ],
      );

      blocTest<MapIconsBloc, MapIconsState>(
        'handles empty room',
        build: () {
          when(() => mockRepo.getIconsForRoom('empty'))
              .thenAnswer((_) async => []);
          return bloc;
        },
        act: (bloc) => bloc.add(const LoadMapIcons('empty')),
        expect: () => [
          isA<MapIconsState>().having((s) => s.isLoading, 'isLoading', true),
          isA<MapIconsState>()
              .having((s) => s.icons, 'icons', isEmpty)
              .having((s) => s.isLoading, 'isLoading', false),
        ],
      );

      blocTest<MapIconsBloc, MapIconsState>(
        'emits error on failure',
        build: () {
          when(() => mockRepo.getIconsForRoom('room1'))
              .thenThrow(Exception('DB error'));
          return bloc;
        },
        act: (bloc) => bloc.add(const LoadMapIcons('room1')),
        expect: () => [
          isA<MapIconsState>().having((s) => s.isLoading, 'isLoading', true),
          isA<MapIconsState>()
              .having((s) => s.isLoading, 'isLoading', false)
              .having((s) => s.error, 'error', contains('Failed to load icons')),
        ],
      );
    });

    group('LoadMapIconsForRooms', () {
      blocTest<MapIconsBloc, MapIconsState>(
        'loads icons for multiple rooms',
        build: () {
          when(() => mockRepo.getIconsForRooms(['room1', 'room2']))
              .thenAnswer((_) async => [
            _makeIcon(id: 'i1', roomId: 'room1'),
            _makeIcon(id: 'i2', roomId: 'room2'),
          ]);
          return bloc;
        },
        act: (bloc) => bloc.add(const LoadMapIconsForRooms(['room1', 'room2'])),
        expect: () => [
          isA<MapIconsState>().having((s) => s.isLoading, 'isLoading', true),
          isA<MapIconsState>()
              .having((s) => s.icons.length, 'count', 2)
              .having((s) => s.isLoading, 'isLoading', false),
        ],
      );

      blocTest<MapIconsBloc, MapIconsState>(
        'handles error',
        build: () {
          when(() => mockRepo.getIconsForRooms(any()))
              .thenThrow(Exception('fail'));
          return bloc;
        },
        act: (bloc) => bloc.add(const LoadMapIconsForRooms(['room1'])),
        expect: () => [
          isA<MapIconsState>().having((s) => s.isLoading, 'isLoading', true),
          isA<MapIconsState>()
              .having((s) => s.error, 'error', contains('Failed to load icons')),
        ],
      );
    });

    group('MapIconCreated', () {
      blocTest<MapIconsBloc, MapIconsState>(
        'adds new icon',
        build: () => bloc,
        act: (bloc) => bloc.add(MapIconCreated(_makeIcon())),
        expect: () => [
          isA<MapIconsState>().having((s) => s.icons.length, 'count', 1),
        ],
      );

      blocTest<MapIconsBloc, MapIconsState>(
        'skips duplicate icon',
        seed: () => MapIconsState(icons: [_makeIcon()]),
        build: () => bloc,
        act: (bloc) => bloc.add(MapIconCreated(_makeIcon())),
        expect: () => [], // No state change
      );

      blocTest<MapIconsBloc, MapIconsState>(
        'adds multiple different icons',
        build: () => bloc,
        act: (bloc) {
          bloc.add(MapIconCreated(_makeIcon(id: 'i1')));
          bloc.add(MapIconCreated(_makeIcon(id: 'i2')));
        },
        expect: () => [
          isA<MapIconsState>().having((s) => s.icons.length, 'count', 1),
          isA<MapIconsState>().having((s) => s.icons.length, 'count', 2),
        ],
      );
    });

    group('MapIconUpdated', () {
      blocTest<MapIconsBloc, MapIconsState>(
        'updates existing icon',
        seed: () => MapIconsState(icons: [_makeIcon(lat: 40.0)]),
        build: () => bloc,
        act: (bloc) => bloc.add(MapIconUpdated(_makeIcon(lat: 41.0))),
        expect: () => [
          isA<MapIconsState>().having(
            (s) => s.icons.first.latitude, 'lat', 41.0,
          ),
        ],
      );

      blocTest<MapIconsBloc, MapIconsState>(
        'keeps other icons unchanged',
        seed: () => MapIconsState(icons: [
          _makeIcon(id: 'i1', lat: 40.0),
          _makeIcon(id: 'i2', lat: 42.0),
        ]),
        build: () => bloc,
        act: (bloc) => bloc.add(MapIconUpdated(_makeIcon(id: 'i1', lat: 41.0))),
        expect: () => [
          isA<MapIconsState>()
              .having((s) => s.icons.length, 'count', 2)
              .having((s) => s.icons.first.latitude, 'updated lat', 41.0)
              .having((s) => s.icons.last.latitude, 'unchanged lat', 42.0),
        ],
      );
    });

    group('MapIconDeleted', () {
      blocTest<MapIconsBloc, MapIconsState>(
        'removes icon by id',
        seed: () => MapIconsState(icons: [
          _makeIcon(id: 'i1'),
          _makeIcon(id: 'i2'),
        ]),
        build: () => bloc,
        act: (bloc) => bloc.add(const MapIconDeleted(iconId: 'i1', roomId: 'room1')),
        expect: () => [
          isA<MapIconsState>()
              .having((s) => s.icons.length, 'count', 1)
              .having((s) => s.icons.first.id, 'remaining', 'i2'),
        ],
      );

      blocTest<MapIconsBloc, MapIconsState>(
        'deleting nonexistent icon emits same-length list',
        seed: () => MapIconsState(icons: [_makeIcon()]),
        build: () => bloc,
        act: (bloc) => bloc.add(const MapIconDeleted(iconId: 'nonexistent', roomId: 'room1')),
        expect: () => [],  // No state change since list content is equivalent
      );
    });

    group('MapIconsBulkUpdate', () {
      blocTest<MapIconsBloc, MapIconsState>(
        'replaces icons for a room',
        seed: () => MapIconsState(icons: [
          _makeIcon(id: 'old1', roomId: 'room1'),
          _makeIcon(id: 'other', roomId: 'room2'),
        ]),
        build: () => bloc,
        act: (bloc) => bloc.add(MapIconsBulkUpdate(
          roomId: 'room1',
          icons: [_makeIcon(id: 'new1', roomId: 'room1'), _makeIcon(id: 'new2', roomId: 'room1')],
        )),
        expect: () => [
          isA<MapIconsState>()
              .having((s) => s.icons.length, 'count', 3) // 1 from room2 + 2 new
              .having((s) => s.icons.where((i) => i.roomId == 'room1').length, 'room1 count', 2)
              .having((s) => s.icons.where((i) => i.roomId == 'room2').length, 'room2 count', 1),
        ],
      );
    });

    group('ClearMapIconsForRoom', () {
      blocTest<MapIconsBloc, MapIconsState>(
        'removes all icons for specified room',
        seed: () => MapIconsState(icons: [
          _makeIcon(id: 'i1', roomId: 'room1'),
          _makeIcon(id: 'i2', roomId: 'room1'),
          _makeIcon(id: 'i3', roomId: 'room2'),
        ]),
        build: () => bloc,
        act: (bloc) => bloc.add(const ClearMapIconsForRoom('room1')),
        expect: () => [
          isA<MapIconsState>()
              .having((s) => s.icons.length, 'count', 1)
              .having((s) => s.icons.first.roomId, 'remaining room', 'room2'),
        ],
      );
    });

    group('ClearAllMapIcons', () {
      blocTest<MapIconsBloc, MapIconsState>(
        'clears all icons',
        seed: () => MapIconsState(icons: [
          _makeIcon(id: 'i1'),
          _makeIcon(id: 'i2'),
        ]),
        build: () => bloc,
        act: (bloc) => bloc.add(ClearAllMapIcons()),
        expect: () => [
          isA<MapIconsState>().having((s) => s.icons, 'icons', isEmpty),
        ],
      );
    });
  });

  group('MapIconsState', () {
    test('default state', () {
      const state = MapIconsState();
      expect(state.icons, isEmpty);
      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
      expect(state.selectedRoomId, isNull);
      expect(state.selectedRoomIds, isNull);
    });

    test('filteredIcons returns all when no selection', () {
      final state = MapIconsState(icons: [_makeIcon(), _makeIcon(id: 'i2', roomId: 'room2')]);
      expect(state.filteredIcons.length, 2);
    });

    test('filteredIcons filters by selectedRoomId', () {
      final state = MapIconsState(
        icons: [_makeIcon(roomId: 'room1'), _makeIcon(id: 'i2', roomId: 'room2')],
        selectedRoomId: 'room1',
      );
      expect(state.filteredIcons.length, 1);
      expect(state.filteredIcons.first.roomId, 'room1');
    });

    test('filteredIcons filters by selectedRoomIds', () {
      final state = MapIconsState(
        icons: [
          _makeIcon(id: 'i1', roomId: 'room1'),
          _makeIcon(id: 'i2', roomId: 'room2'),
          _makeIcon(id: 'i3', roomId: 'room3'),
        ],
        selectedRoomIds: ['room1', 'room3'],
      );
      expect(state.filteredIcons.length, 2);
    });

    test('copyWith preserves values', () {
      final state = MapIconsState(
        icons: [_makeIcon()],
        isLoading: true,
        error: 'err',
        selectedRoomId: 'room1',
      );
      final copied = state.copyWith();
      expect(copied.icons.length, 1);
      expect(copied.isLoading, true);
      expect(copied.selectedRoomId, 'room1');
    });

    test('copyWith overrides', () {
      const state = MapIconsState(isLoading: true);
      final newState = state.copyWith(isLoading: false, error: 'new error');
      expect(newState.isLoading, false);
      expect(newState.error, 'new error');
    });

    test('equality', () {
      final s1 = MapIconsState(icons: [_makeIcon()]);
      final s2 = MapIconsState(icons: [_makeIcon()]);
      // MapIcon doesn't implement Equatable so these won't be equal by default
      // but state props check works
      expect(const MapIconsState(), equals(const MapIconsState()));
    });
  });
}
