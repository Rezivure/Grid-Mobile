import 'package:flutter/foundation.dart';

enum InAppNotificationVariant { info, success, warning, error }

class InAppNotificationAction {
  final String label;
  final VoidCallback onTap;
  const InAppNotificationAction({required this.label, required this.onTap});
}

class InAppNotification {
  final String id;
  final String title;
  final String? message;
  final InAppNotificationVariant variant;
  final Duration duration;
  final VoidCallback? onTap;
  final InAppNotificationAction? action;

  InAppNotification({
    required this.id,
    required this.title,
    this.message,
    this.variant = InAppNotificationVariant.info,
    required this.duration,
    this.onTap,
    this.action,
  });
}

/// In-app toast/banner controller. Push notifications and snackbar
/// replacements share this same queue so the visual style stays consistent
/// across foreground feedback and APNS/FCM payloads.
class InAppNotifier extends ChangeNotifier {
  InAppNotifier._();
  static final InAppNotifier instance = InAppNotifier._();

  final List<InAppNotification> _items = [];
  int _seq = 0;

  List<InAppNotification> get items => List.unmodifiable(_items);

  InAppNotification show({
    required String title,
    String? message,
    InAppNotificationVariant variant = InAppNotificationVariant.info,
    Duration? duration,
    VoidCallback? onTap,
    InAppNotificationAction? action,
  }) {
    final id = 'ian-${DateTime.now().millisecondsSinceEpoch}-${_seq++}';
    final dur = duration ??
        (message != null && message.isNotEmpty
            ? const Duration(seconds: 6)
            : const Duration(seconds: 4));
    final n = InAppNotification(
      id: id,
      title: title,
      message: message,
      variant: variant,
      duration: dur,
      onTap: onTap,
      action: action,
    );
    _items.add(n);
    notifyListeners();
    return n;
  }

  void dismiss(InAppNotification n) {
    final removed = _items.remove(n);
    if (removed) notifyListeners();
  }

  void clear() {
    if (_items.isEmpty) return;
    _items.clear();
    notifyListeners();
  }
}
