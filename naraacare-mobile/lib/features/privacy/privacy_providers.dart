import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naraacare/core/providers.dart';
import 'package:naraacare/features/privacy/data/privacy_api.dart';

final privacyApiProvider = Provider<PrivacyApi>(
  (ref) => PrivacyApi(ref.watch(apiClientProvider)),
);

final FutureProvider<PrivacyStatus> privacyStatusProvider =
    FutureProvider.autoDispose<PrivacyStatus>(
      (ref) => ref.watch(privacyApiProvider).status(),
    );

final FutureProvider<List<ConsentState>> consentsProvider =
    FutureProvider.autoDispose<List<ConsentState>>(
      (ref) => ref.watch(privacyApiProvider).consents(),
    );
