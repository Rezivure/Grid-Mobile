import 'package:flutter_test/flutter_test.dart';
import 'package:grid_frontend/services/vod_init_error.dart';

void main() {
  group('isDuplicateVodInitError', () {
    test('accepts the known duplicate-init StateError', () {
      expect(
        isDuplicateVodInitError(
          StateError('Should not initialize flutter_rust_bridge twice'),
        ),
        isTrue,
      );
    });

    test('rejects a codegen/runtime version mismatch', () {
      expect(
        isDuplicateVodInitError(
          StateError(
            "flutter_vodozemac's codegen version (1.0.0) should be "
            'the same as runtime version (2.0.0). '
            'See https://cjycode.com/flutter_rust_bridge/guides/miscellaneous/upgrade/regular for details.',
          ),
        ),
        isFalse,
      );
    });

    test('rejects errors that only mention already or twice', () {
      expect(
        isDuplicateVodInitError(StateError('already initialized')),
        isFalse,
      );
      expect(
        isDuplicateVodInitError(Exception('called twice')),
        isFalse,
      );
    });
  });
}
