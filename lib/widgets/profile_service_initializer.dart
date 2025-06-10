import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:grid_frontend/providers/profile_picture_provider.dart';
import 'package:grid_frontend/services/message_processor.dart';

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
      MessageProcessor.othersProfileService.setProfilePictureProvider(provider);
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}