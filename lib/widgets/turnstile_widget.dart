import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// A widget that displays a Cloudflare Turnstile challenge via WebView.
/// Returns the turnstile token via [onTokenReceived] callback.
class TurnstileWidget extends StatefulWidget {
  final String siteKey;
  final ValueChanged<String> onTokenReceived;
  final VoidCallback? onError;

  const TurnstileWidget({
    Key? key,
    required this.siteKey,
    required this.onTokenReceived,
    this.onError,
  }) : super(key: key);

  @override
  State<TurnstileWidget> createState() => _TurnstileWidgetState();
}

class _TurnstileWidgetState extends State<TurnstileWidget> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();

    final html = '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <script src="https://challenges.cloudflare.com/turnstile/v0/api.js" async defer></script>
  <style>
    body {
      margin: 0;
      padding: 0;
      display: flex;
      justify-content: center;
      align-items: center;
      min-height: 80px;
      background: transparent;
    }
  </style>
</head>
<body>
  <div id="turnstile-container"></div>
  <script>
    function onTurnstileLoad() {
      turnstile.render('#turnstile-container', {
        sitekey: '${widget.siteKey}',
        callback: function(token) {
          TurnstileCallback.postMessage(token);
        },
        'error-callback': function() {
          TurnstileError.postMessage('error');
        },
        theme: 'auto',
        size: 'normal',
      });
    }

    // Wait for turnstile API to load
    if (typeof turnstile !== 'undefined') {
      onTurnstileLoad();
    } else {
      document.addEventListener('DOMContentLoaded', function() {
        // Small delay to ensure turnstile script is loaded
        setTimeout(function() {
          if (typeof turnstile !== 'undefined') {
            onTurnstileLoad();
          }
        }, 500);
      });
    }
  </script>
</body>
</html>
''';

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel(
        'TurnstileCallback',
        onMessageReceived: (message) {
          widget.onTokenReceived(message.message);
        },
      )
      ..addJavaScriptChannel(
        'TurnstileError',
        onMessageReceived: (message) {
          widget.onError?.call();
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) {
              setState(() => _isLoading = false);
            }
          },
        ),
      )
      ..loadHtmlString(html);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 80,
      child: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
    );
  }
}
