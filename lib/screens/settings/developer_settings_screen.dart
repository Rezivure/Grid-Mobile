import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:grid_frontend/services/debug_log_service.dart';

class DeveloperSettingsScreen extends StatefulWidget {
  const DeveloperSettingsScreen({Key? key}) : super(key: key);

  @override
  State<DeveloperSettingsScreen> createState() => _DeveloperSettingsScreenState();
}

class _DeveloperSettingsScreenState extends State<DeveloperSettingsScreen> {
  final _endpointController = TextEditingController();
  bool _enabled = false;
  bool _testing = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    final service = DebugLogService.instance;
    _enabled = service.enabled;
    _endpointController.text = service.endpoint ?? 'http://100.83.161.78:9999/logs';
  }

  @override
  void dispose() {
    _endpointController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() { _testing = true; _testResult = null; });
    // Save endpoint first
    await DebugLogService.instance.setEndpoint(_endpointController.text.trim());
    final success = await DebugLogService.instance.testConnection();
    setState(() {
      _testing = false;
      _testResult = success ? '✓ Connected successfully' : '✗ Connection failed';
    });
  }

  void _openDashboard() {
    final endpoint = _endpointController.text.trim();
    final dashboardUrl = endpoint.replaceAll('/logs', '');
    launchUrl(Uri.parse(dashboardUrl), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Developer Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Enable toggle
          SwitchListTile(
            title: const Text('Enable Debug Logging'),
            subtitle: Text(_enabled ? 'Logs are being sent' : 'Logging disabled'),
            value: _enabled,
            onChanged: (val) async {
              await DebugLogService.instance.setEnabled(val);
              setState(() { _enabled = val; });
            },
          ),
          const SizedBox(height: 16),

          // Endpoint field
          Text('Log Endpoint URL', style: TextStyle(
            fontWeight: FontWeight.w600,
            color: colorScheme.onBackground.withOpacity(0.7),
          )),
          const SizedBox(height: 8),
          TextField(
            controller: _endpointController,
            decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              hintText: 'http://100.83.161.78:9999/logs',
            ),
            onChanged: (val) {
              DebugLogService.instance.setEndpoint(val.trim());
            },
          ),
          const SizedBox(height: 16),

          // Buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _testing ? null : _testConnection,
                  icon: _testing
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.network_check),
                  label: const Text('Test Connection'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openDashboard,
                  icon: const Icon(Icons.open_in_browser),
                  label: const Text('View Dashboard'),
                ),
              ),
            ],
          ),

          if (_testResult != null) ...[
            const SizedBox(height: 12),
            Text(
              _testResult!,
              style: TextStyle(
                color: _testResult!.startsWith('✓') ? Colors.green : Colors.red,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],

          const SizedBox(height: 24),
          // Status
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colorScheme.outline.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                Text('Enabled: ${_enabled ? "Yes" : "No"}'),
                Text('Endpoint: ${_endpointController.text}'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
