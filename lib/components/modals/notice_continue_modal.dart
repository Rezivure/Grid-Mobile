import 'package:flutter/material.dart';

class NoticeContinueModal extends StatelessWidget {
  final String message;
  final VoidCallback? onContinue;

  const NoticeContinueModal({
    Key? key,
    required this.message,
    this.onContinue,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: colorScheme.onBackground),
          ),
          SizedBox(height: 20),
          Center(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.onSurface,
                foregroundColor: colorScheme.surface,
              ),
              onPressed: () {
                Navigator.of(context).pop(); // Close the modal
                if (onContinue != null) {
                  onContinue!(); // Trigger the callback if provided
                }
              },
              child: Text("Continue"),
            ),
          ),
        ],
      ),
    );
  }
}
