import "package:flutter/cupertino.dart";
import "package:flutter/material.dart";

import "../../styles/grid_colors.dart";

class GridCircularProgressIndicator extends StatelessWidget {
  static const double _appleDefaultRadius = 15;

  final bool isPrimary;
  final double? value;

  const GridCircularProgressIndicator.progress({
    super.key,
    bool? primary,
    required this.value,
  }) : isPrimary = primary ?? true;

  const GridCircularProgressIndicator({Key? key, bool? isPrimary, bool loading = true})
      : this.progress(
          key: key,
          primary: isPrimary,
          value: loading ? null : 0,
        );

  @override
  Widget build(BuildContext context) {
    ThemeData theme = Theme.of(context);

    Color color = isPrimary ? Colors.black : context.gridColors.mint;

    TargetPlatform platform = theme.platform;

    bool loading = value == null;

    switch (platform) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        if (loading) {
          return CupertinoActivityIndicator(radius: _appleDefaultRadius, color: color);
        }
        return CupertinoActivityIndicator.partiallyRevealed(
          radius: _appleDefaultRadius,
          progress: value!,
          color: color,
        );
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        return CircularProgressIndicator(
          value: value,
          color: color,
          strokeWidth: 2,
        );
    }
  }
}
