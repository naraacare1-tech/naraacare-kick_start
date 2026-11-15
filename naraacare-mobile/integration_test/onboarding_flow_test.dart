import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/features/sign_up_to_home_flow.dart';

/// On a device/emulator, against the mocked API:
/// `flutter test integration_test --flavor dev`.
/// Staging E2E with real email and providers (patrol) is S16.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('first run: sign up -> onboarding -> Home', signUpToHome);
}
