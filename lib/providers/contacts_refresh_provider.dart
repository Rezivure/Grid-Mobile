import 'package:flutter/material.dart';

class ContactsRefreshProvider extends ChangeNotifier {
  void refreshContacts() {
    notifyListeners();
  }
}