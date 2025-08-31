import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:grid_frontend/blocs/invitations/invitations_event.dart';
import 'package:grid_frontend/blocs/invitations/invitations_state.dart';
import 'package:grid_frontend/repositories/invitations_repository.dart';

class InvitationsBloc extends Bloc<InvitationsEvent, InvitationsState> {
  final InvitationsRepository _repository;
  List<Map<String, dynamic>> _invitations = [];

  InvitationsBloc({required InvitationsRepository repository})
      : _repository = repository,
        super(InvitationsInitial()) {
    on<LoadInvitations>(_onLoadInvitations);
    on<AddInvitation>(_onAddInvitation);
    on<RemoveInvitation>(_onRemoveInvitation);
    on<ClearInvitations>(_onClearInvitations);
    on<ProcessSyncInvitation>(_onProcessSyncInvitation);
  }

  Future<void> _onLoadInvitations(
    LoadInvitations event,
    Emitter<InvitationsState> emit,
  ) async {
    emit(InvitationsLoading());
    try {
      _invitations = await _repository.loadInvitations();
      emit(InvitationsLoaded(_invitations));
    } catch (e) {
      emit(InvitationsError('Failed to load invitations: $e'));
    }
  }

  Future<void> _onAddInvitation(
    AddInvitation event,
    Emitter<InvitationsState> emit,
  ) async {
    try {
      // Check if invitation already exists
      final exists = _invitations.any(
        (invite) => invite['roomId'] == event.invitation['roomId'],
      );
      
      if (!exists) {
        _invitations.add(event.invitation);
        await _repository.saveInvitations(_invitations);
        emit(InvitationsLoaded(List.from(_invitations)));
      }
    } catch (e) {
      emit(InvitationsError('Failed to add invitation: $e'));
    }
  }

  Future<void> _onRemoveInvitation(
    RemoveInvitation event,
    Emitter<InvitationsState> emit,
  ) async {
    try {
      print('[InvitationsBloc] Removing invitation for room ${event.roomId}');
      final beforeCount = _invitations.length;
      _invitations.removeWhere((invite) => invite['roomId'] == event.roomId);
      final afterCount = _invitations.length;
      
      if (beforeCount != afterCount) {
        await _repository.saveInvitations(_invitations);
        emit(InvitationsLoaded(List.from(_invitations)));
        print('[InvitationsBloc] Successfully removed invitation. Before: $beforeCount, After: $afterCount');
      } else {
        print('[InvitationsBloc] Warning: Invitation not found for room ${event.roomId}');
      }
    } catch (e) {
      print('[InvitationsBloc] Error removing invitation: $e');
      emit(InvitationsError('Failed to remove invitation: $e'));
    }
  }

  Future<void> _onClearInvitations(
    ClearInvitations event,
    Emitter<InvitationsState> emit,
  ) async {
    try {
      _invitations.clear();
      await _repository.clearInvitations();
      emit(InvitationsLoaded([]));
    } catch (e) {
      emit(InvitationsError('Failed to clear invitations: $e'));
    }
  }

  Future<void> _onProcessSyncInvitation(
    ProcessSyncInvitation event,
    Emitter<InvitationsState> emit,
  ) async {
    try {
      // Check if invitation already exists
      final exists = _invitations.any(
        (invite) => invite['roomId'] == event.roomId,
      );
      
      if (!exists) {
        final invitation = {
          'roomId': event.roomId,
          'inviter': event.inviter,
          'roomName': event.roomName,
          'inviteState': event.inviteState,
        };
        
        _invitations.add(invitation);
        await _repository.saveInvitations(_invitations);
        emit(InvitationsLoaded(List.from(_invitations)));
        
        print('[InvitationsBloc] Added new invitation from ${event.inviter} for room ${event.roomName}. Total: ${_invitations.length}');
      }
    } catch (e) {
      emit(InvitationsError('Failed to process sync invitation: $e'));
    }
  }

  // Helper method to get current invitations
  List<Map<String, dynamic>> get invitations => List.from(_invitations);
  
  // Helper method to get total count
  int get totalInvites => _invitations.length;
}