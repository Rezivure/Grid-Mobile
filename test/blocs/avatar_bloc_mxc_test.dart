import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grid_frontend/blocs/avatar/avatar_bloc.dart';
import 'package:grid_frontend/blocs/avatar/avatar_event.dart';
import 'package:matrix/matrix.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockClient extends Mock implements Client {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockClient client;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    client = _MockClient();
    when(() => client.isLogged()).thenReturn(true);
    when(() => client.accessToken).thenReturn('token');
    when(() => client.homeserver).thenReturn(Uri.parse('https://example.org'));
    // The test only needs to see which download path is taken.
    when(() => client.getContent(any(), any()))
        .thenThrow(Exception('download stopped by the test'));
  });

  test('an mxc:// avatar flagged as not Matrix is downloaded from Matrix',
      () async {
    final bloc = AvatarBloc(client: client);
    bloc.add(AvatarUpdateReceived(
      userId: '@me:example.org',
      avatarUrl: 'mxc://example.org/abc123',
      encryptionKey: 'key',
      encryptionIv: 'iv',
      isMatrixUrl: false,
    ));

    await untilCalled(() => client.getContent(any(), any()))
        .timeout(const Duration(seconds: 5));
    verify(() => client.getContent('example.org', 'abc123')).called(1);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('avatar_is_matrix_@me:example.org'), isTrue);
    await bloc.close();
  });
}
