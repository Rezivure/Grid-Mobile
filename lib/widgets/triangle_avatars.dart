import 'package:flutter/material.dart';

import '../utilities/utils.dart';
import 'grid/grid_avatar.dart';
import 'two_user_avatars.dart';

class TriangleAvatars extends StatelessWidget {
  final List<String> userIds;

  const TriangleAvatars({super.key, required this.userIds});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (userIds.isEmpty) {
      return CircleAvatar(
        radius: 30,
        backgroundColor: colorScheme.primary.withOpacity(0.2),
        child: Icon(
          Icons.group_off,
          color: colorScheme.primary,
          size: 30,
        ),
      );
    }

    if (userIds.length == 1) {
      return CircleAvatar(
        radius: 30,
        backgroundColor: colorScheme.primary.withOpacity(0.1),
        child: ClipOval(
          child: GridAvatarFallback(
            name: localpart(userIds[0]),
            size: 40,
          ),
        ),
      );
    }

    if (userIds.length == 2) {
      return TwoUserAvatars(userIds: userIds);
    }

    final displayedUserIds = userIds.take(3).toList();

    return CircleAvatar(
      radius: 30,
      backgroundColor: Colors.grey.shade200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: 6,
            child: ClipOval(
              child: GridAvatarFallback(
                name: localpart(displayedUserIds[0]),
                size: 28,
              ),
            ),
          ),
          Positioned(
            bottom: 6,
            left: 6,
            child: ClipOval(
              child: GridAvatarFallback(
                name: localpart(displayedUserIds[1]),
                size: 28,
              ),
            ),
          ),
          Positioned(
            bottom: 6,
            right: 6,
            child: ClipOval(
              child: GridAvatarFallback(
                name: localpart(displayedUserIds[2]),
                size: 28,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
