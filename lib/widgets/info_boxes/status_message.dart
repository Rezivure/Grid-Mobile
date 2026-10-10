import 'package:flutter/material.dart';
import 'package:grid_frontend/widgets/layout/gap.dart';

class StatusMessage extends StatelessWidget {
  final Color? color;
  final IconData? icon;
  final Widget text;

  const StatusMessage({super.key, this.color, this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color?.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: color,
          ),
          Gap.small,
          Expanded(
            child: DefaultTextStyle.merge(
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              child: text,
            ),
          ),
        ],
      ),
    );
  }
}
