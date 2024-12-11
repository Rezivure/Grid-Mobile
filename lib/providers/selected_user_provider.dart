import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:latlong2/latlong.dart';
import 'package:grid_frontend/blocs/map/map_bloc.dart';
import 'package:grid_frontend/blocs/map/map_event.dart';

class SelectedUserProvider with ChangeNotifier {
  String? _selectedUserId;

  String? get selectedUserId => _selectedUserId;

  void setSelectedUserId(String? userId, BuildContext context) {
    print("Selected user: $userId");
    _selectedUserId = userId;

    // Trigger map navigation via MapBloc
    if (userId != null) {
      context.read<MapBloc>().add(MapMoveToUser(userId));
    }
    notifyListeners();
  }
}
