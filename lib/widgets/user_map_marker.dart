import 'package:flutter/material.dart';
import 'package:random_avatar/random_avatar.dart';

class UserMapMarker extends StatefulWidget {
  final String userId;

  UserMapMarker({required this.userId});

  @override
  _UserMapMarkerState createState() => _UserMapMarkerState();
}

class _UserMapMarkerState extends State<UserMapMarker>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double>? _animation;

  @override
  void initState() {
    super.initState();

    // Set up the animation controller and animation
    _controller = AnimationController(
      vsync: this,
      duration: Duration(seconds: 1), // 1-second pulse
    )..repeat(reverse: true); // Repeat animation indefinitely

    _animation = Tween<double>(begin: 1.0, end: 1.3).animate(_controller!);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation!,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            // Pulsing border
            Container(
              width: 50 * _animation!.value,
              height: 50 * _animation!.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.green.withOpacity(0.4), // Green with transparency
              ),
            ),
            // User Avatar with static border
            Container(
              padding: EdgeInsets.all(3), // Border width
              decoration: BoxDecoration(
                color: Colors.white, // Static white border inside the pulse
                shape: BoxShape.circle,
              ),
              child: ClipOval(
                child: RandomAvatar(
                  widget.userId.split(':')[0].replaceFirst('@', ''),
                  height: 40,
                  width: 40,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
