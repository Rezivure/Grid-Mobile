import 'package:flutter/material.dart';

class UserHandleTextField extends StatelessWidget {
  final TextEditingController? controller;

  const UserHandleTextField({super.key, this.controller});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: 'Handle',
        hintText: 'Enter your unique handle',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        filled: true,
        fillColor: Colors.transparent,
        contentPadding: const EdgeInsets.all(20),
        prefixIcon: Icon(
          Icons.person_outline,
          color: ColorScheme.of(context).primary,
        ),
      ),
    );
  }
}
