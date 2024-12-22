import 'package:flutter/material.dart';
import 'package:random_avatar/random_avatar.dart';
import '../utilities/utils.dart';
import 'two_user_avatars.dart';

class TriangleAvatars extends StatelessWidget {
  final List<String> userIds;

  const TriangleAvatars({super.key, required this.userIds});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Handle empty case
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

    // Handle single member case
    if (userIds.length == 1) {
      return CircleAvatar(
        radius: 30,
        backgroundColor: colorScheme.primary.withOpacity(0.1),
        child: Stack(
          alignment: Alignment.center,
          children: [
            RandomAvatar(
              localpart(userIds[0]),
              height: 40,
              width: 40,
            ),

          ],
        ),
      );
    }

    // Handle two member case
    if (userIds.length == 2) {
      return TwoUserAvatars(userIds: userIds);
    }

    // Handle three or more members case
    List<String> displayedUserIds = userIds.take(3).toList();

    return CircleAvatar(
      radius: 30,
      backgroundColor: Colors.grey.shade200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: 6,
            child: RandomAvatar(
              localpart(displayedUserIds[0]),
              height: 28,
              width: 28,
            ),
          ),
          Positioned(
            bottom: 6,
            left: 6,
            child: RandomAvatar(
              localpart(displayedUserIds[1]),
              height: 28,
              width: 28,
            ),
          ),
          Positioned(
            bottom: 6,
            right: 6,
            child: RandomAvatar(
              localpart(displayedUserIds[2]),
              height: 28,
              width: 28,
            ),
          ),
        ],
      ),
    );
  }
}