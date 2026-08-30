import 'package:flutter/foundation.dart';

import '../models/contact_display.dart';

/// Holds the currently-presented contact for the inline profile sheet
/// that MapTab renders inside its Stack. Using a singleton notifier
/// (rather than `showModalBottomSheet`) lets the underlying map remain
/// tappable / pannable while the sheet is up, which a modal route
/// can't do.
///
/// `open()` from anywhere — drawer tap or marker tap. `close()` from
/// the sheet's close button or swipe-down. MapTab listens in
/// initState and renders the sheet when `contact != null`.
class ContactSheetController extends ChangeNotifier {
  ContactSheetController._();
  static final ContactSheetController instance = ContactSheetController._();

  ContactDisplay? _contact;
  ContactDisplay? get contact => _contact;

  /// Whether a contact profile sheet is currently presented. Used by the
  /// background list sheet to collapse itself out of the way (#305).
  bool get isOpen => _contact != null;

  void open(ContactDisplay contact) {
    _contact = contact;
    notifyListeners();
  }

  void close() {
    if (_contact == null) return;
    _contact = null;
    notifyListeners();
  }
}
