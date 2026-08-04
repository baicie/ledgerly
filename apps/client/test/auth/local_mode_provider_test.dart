import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledgerly_client/auth/auth_controller.dart';
import 'package:ledgerly_client/presentation/providers.dart';

void main() {
  test('local mode does not construct the remote authentication repository',
      () {
    var remoteRepositoryRead = false;
    final container = ProviderContainer(
      overrides: [
        apiEndpointProvider.overrideWithValue(null),
        authRepositoryProvider.overrideWith((ref) {
          remoteRepositoryRead = true;
          throw StateError('remote authentication must stay inactive');
        }),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(authControllerProvider);

    expect(controller.state.status, AuthStatus.local);
    expect(remoteRepositoryRead, isFalse);
  });
}
