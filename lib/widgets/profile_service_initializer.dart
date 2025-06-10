import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:grid_frontend/providers/profile_picture_provider.dart';
import 'package:grid_frontend/services/message_processor.dart';
import 'package:grid_frontend/blocs/contacts/contacts_bloc.dart';
import 'package:grid_frontend/blocs/groups/groups_bloc.dart';
import 'package:matrix/matrix.dart' as matrix;

class ProfileServiceInitializer extends StatefulWidget {
  final Widget child;
  
  const ProfileServiceInitializer({Key? key, required this.child}) : super(key: key);
  
  @override
  _ProfileServiceInitializerState createState() => _ProfileServiceInitializerState();
}

class _ProfileServiceInitializerState extends State<ProfileServiceInitializer> {
  @override
  void initState() {
    super.initState();
    // Initialize the connection between OthersProfileService and ProfilePictureProvider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<ProfilePictureProvider>(context, listen: false);
      final contactsBloc = context.read<ContactsBloc>();
      final groupsBloc = context.read<GroupsBloc>();
      final client = Provider.of<matrix.Client>(context, listen: false);
      
      // Set the client in ProfilePictureProvider so it can load current user's picture
      provider.setClient(client);
      
      MessageProcessor.othersProfileService.setProfilePictureProvider(provider);
      MessageProcessor.othersProfileService.setContactsBloc(contactsBloc);
      MessageProcessor.othersProfileService.setGroupsBloc(groupsBloc);
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}