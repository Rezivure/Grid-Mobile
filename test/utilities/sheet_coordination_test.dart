import 'package:flutter_test/flutter_test.dart';
import 'package:grid_frontend/utilities/sheet_coordination.dart';

void main() {
  group('backgroundSheetTargetExtent (#305 double-menu overlay)', () {
    test('no overlay open -> never moves the list sheet', () {
      expect(
        backgroundSheetTargetExtent(
          overlayOpen: false,
          minExtent: 0.3,
          currentExtent: 0.7,
        ),
        isNull,
      );
    });

    test('overlay open + list sheet expanded -> collapse to minimum', () {
      expect(
        backgroundSheetTargetExtent(
          overlayOpen: true,
          minExtent: 0.3,
          currentExtent: 0.7,
        ),
        0.3,
      );
    });

    test('overlay open but list sheet already at minimum -> no movement', () {
      expect(
        backgroundSheetTargetExtent(
          overlayOpen: true,
          minExtent: 0.3,
          currentExtent: 0.3,
        ),
        isNull,
      );
    });

    test('overlay open but list sheet below minimum -> no movement', () {
      expect(
        backgroundSheetTargetExtent(
          overlayOpen: true,
          minExtent: 0.3,
          currentExtent: 0.1,
        ),
        isNull,
      );
    });

    test('overlay open + list sheet just above minimum -> collapse', () {
      expect(
        backgroundSheetTargetExtent(
          overlayOpen: true,
          minExtent: 0.3,
          currentExtent: 0.31,
        ),
        0.3,
      );
    });
  });
}
