import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

class UserInfoBubble extends StatelessWidget {
  final String userId;
  final String userName;
  final LatLng position;
  final VoidCallback? onClose; // Add this line

  UserInfoBubble({
    required this.userId,
    required this.userName,
    required this.position,
    this.onClose, // Add this line
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Positioned(
      top: 100,
      left: MediaQuery.of(context).size.width * 0.2, // Adjust for centering
      right: MediaQuery.of(context).size.width * 0.2, // Adjust for centering
      child: Material(
        elevation: 4.0,
        borderRadius: BorderRadius.circular(8.0),
        child: Container(
          padding: EdgeInsets.all(8.0), // Reduce padding
          constraints: BoxConstraints(maxWidth: 200), // Constrain the width
          decoration: BoxDecoration(
            color: colorScheme.surface, // Use theme surface color
            borderRadius: BorderRadius.circular(8.0),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withOpacity(0.5), // Adapt shadow to theme
                blurRadius: 4.0,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                userName,
                style: TextStyle(
                  fontSize: 16.0,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface, // Adapt text color to theme
                ),
              ),
              SizedBox(height: 4.0), // Reduce the space between elements
              Text(
                'Position: ${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}',
                style: TextStyle(
                  fontSize: 14.0,
                  color: colorScheme.onSurface.withOpacity(0.7), // Adapt text color to theme
                ),
              ),
              SizedBox(height: 8.0),
              ElevatedButton(
                onPressed: onClose ?? () {}, // Use the onClose callback
                child: Text('Close'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.primary, // Use theme primary color for background
                  foregroundColor: colorScheme.onPrimary, // Use onPrimary for text color
                  padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0), // Smaller button padding
                  textStyle: TextStyle(fontSize: 14.0), // Smaller button text
                ),
              )

            ],
          ),
        ),
      ),
    );
  }
}
