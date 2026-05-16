import 'package:flutter/material.dart';

import '../utilities/utils.dart';
import 'grid/grid_avatar.dart';

class TwoUserAvatars extends StatelessWidget {
  final List<String> userIds;

  const TwoUserAvatars({super.key, required this.userIds});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Ensure there are at least two distinct avatars
    List<String> displayedUserIds = userIds.toSet().toList();
    
    // Fix the original empty list bug that was causing RangeError
    if (displayedUserIds.isEmpty) {
      displayedUserIds = ['default_user_1', 'default_user_2'];
    } else if (displayedUserIds.length < 2) {
      displayedUserIds.add(displayedUserIds[0]);
    }
    
    displayedUserIds = displayedUserIds.take(2).toList();

    return CircleAvatar(
      radius: 30,
      backgroundColor: colorScheme.primary.withOpacity(0.1),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: 6,
            left: 6,
            child: ClipOval(
              child: GridAvatarFallback(
                name: localpart(displayedUserIds[0]),
                size: 32,
              ),
            ),
          ),
          Positioned(
            bottom: 6,
            right: 6,
            child: ClipOval(
              child: GridAvatarFallback(
                name: localpart(displayedUserIds[1]),
                size: 32,
              ),
            ),
          ),
        ],
      ),
    );
  }
}