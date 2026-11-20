import 'package:flutter/material.dart';
import 'package:grid_frontend/widgets/buttons/retry_button.dart';
import 'package:grid_frontend/widgets/layout/gap.dart';

Future<bool> showMapErrorDialog(BuildContext context) async {
  bool? retry = await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return MapErrorDialog();
    },
  );

  return retry ?? false;
}

class MapErrorDialog extends StatelessWidget {
  const MapErrorDialog({super.key});

  @override
  Widget build(BuildContext context) {
    ColorScheme scheme = ColorScheme.of(context);
    TextTheme textTheme = TextTheme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      elevation: 0,
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Error icon with animation
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.wifi_off_rounded,
                size: 48,
                color: Colors.orange,
              ),
            ),

            const SizedBox(height: 24),

            // Title
            Text(
              'Connection Error',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),

            Gap.big,

            // Content
            Text(
              'Failed to connect and load Grid. Please check your internet connection.',
              textAlign: TextAlign.center,
              style: textTheme.bodyLarge?.copyWith(
                color: scheme.onSurface.withOpacity(0.7),
                height: 1.4,
              ),
            ),

            const SizedBox(height: 24),

            // Single retry button that restarts the app
            SizedBox(
              width: double.infinity,
              child: RetryButton(
                onPressed: () => _onRetry(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onRetry(BuildContext context) => Navigator.of(context).pop(true);
}
