import 'package:flutter/material.dart';
import 'package:random_avatar/random_avatar.dart';

import '../utilities/utils.dart';

class TwoUserAvatars extends StatelessWidget {
  final List<String> userIds;

  const TwoUserAvatars({super.key, required this.userIds});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Ensure there are at least two distinct avatars
    List<String> displayedUserIds = userIds.toSet().toList();
    if (displayedUserIds.length < 2) {
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
            child: RandomAvatar(
              localpart(displayedUserIds[0]),
              height: 32,
              width: 32,
            ),
          ),
          Positioned(
            bottom: 6,
            right: 6,
            child: RandomAvatar(
              localpart(displayedUserIds[1]),
              height: 32,
              width: 32,
            ),
          ),
        ],
      ),
    );
  }
}