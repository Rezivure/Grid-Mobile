// lib/widgets/user_keys_modal.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:grid_frontend/services/database_service.dart';

class UserKeysModal extends StatelessWidget {
  final String userId;
  final bool approvedKeys;

  UserKeysModal({
    required this.userId,
    required this.approvedKeys,
  });

  Future<Map<String, dynamic>?> _fetchDeviceKeys(BuildContext context) async {
    final databaseService = Provider.of<DatabaseService>(context, listen: false);
    return await databaseService.getDeviceKeysByUserId(userId);
  }

  void approveKeys(BuildContext context) async {
    final databaseService = Provider.of<DatabaseService>(context, listen: false);

    try {
      await databaseService.updateApprovedKeys(this.userId, true);

      // Notify the parent widget that keys were approved
      Navigator.of(context).pop(true);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('User keys verified.')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to verify user keys.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurfaceColor = theme.colorScheme.onSurface;
    final surfaceColor = theme.colorScheme.surface;

    return AlertDialog(
      title: Text('Safety Number'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 10),
          Row(
            children: [
              Icon(
                approvedKeys ? Icons.lock : Icons.lock_open,
                color: approvedKeys ? Colors.green : Colors.red,
              ),
              SizedBox(width: 8),
              Text(
                approvedKeys ? 'Keys Verified' : 'Safety Number has Changed',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: approvedKeys ? Colors.green : Colors.red,
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          Text(
            approvedKeys
                ? 'This user’s keys are verified and trusted for secure communication.'
                : 'This user’s keys are not verified. Keys change when a user potentially logs in from a new device, or their account may have been compromised. Verify their Device ID below:',
            style: TextStyle(fontSize: 14),
          ),
          SizedBox(height: 10),
          if (!approvedKeys)
            FutureBuilder<Map<String, dynamic>?>(
              future: _fetchDeviceKeys(context),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return CircularProgressIndicator();
                } else if (snapshot.hasError) {
                  return Text(
                    'Error loading device keys',
                    style: TextStyle(color: Colors.red),
                  );
                } else if (!snapshot.hasData || snapshot.data == null) {
                  return Text(
                    'No device keys found for this user.',
                    style: TextStyle(color: Colors.grey),
                  );
                } else {
                  final deviceKeys = snapshot.data!;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: deviceKeys.keys.map((deviceId) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Text(
                          'Device ID: $deviceId',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      );
                    }).toList(),
                  );
                }
              },
            ),
        ],
      ),
      actions: [
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: surfaceColor,
            foregroundColor: Colors.red,
          ),
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Close'),
        ),
        if (!approvedKeys)
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: onSurfaceColor,
              foregroundColor: surfaceColor,
            ),
            onPressed: () {
              approveKeys(context);
            },
            child: Text('Verify Keys'),
          ),
      ],
    );
  }
}
