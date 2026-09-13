import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:grid_frontend/styles/grid_colors.dart';

/// The "Terms & Privacy" link that sits inline in the consent sentence.
///
/// This is an [InlineSpan] rather than a widget on purpose: a `WidgetSpan`
/// is laid out as one atomic box, so on narrow screens (320px devices leave
/// 272px inside the welcome screen's 24px padding) it cannot wrap mid-phrase
/// and pushes the sentence onto an extra line.
///
/// The caller owns [recognizer] and is responsible for disposing it.
class TermsAndPrivacyLink {
  const TermsAndPrivacyLink._();

  // TODO(Yuki): localize
  static const String label = 'Terms & Privacy';

  static InlineSpan span({
    required BuildContext context,
    required TapGestureRecognizer recognizer,
  }) {
    return TextSpan(
      text: label,
      style: TextStyle(
        color: context.gridColors.text2,
        decoration: TextDecoration.underline,
      ),
      recognizer: recognizer,
    );
  }
}
