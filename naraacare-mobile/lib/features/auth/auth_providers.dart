import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naraacare/core/config/providers.dart';
import 'package:naraacare/core/providers.dart';
import 'package:naraacare/features/auth/data/auth_api.dart';
import 'package:naraacare/features/auth/data/social_sign_in.dart';

final authApiProvider = Provider<AuthApi>(
  (ref) =>
      AuthApi(ref.watch(apiClientProvider), ref.watch(secureStorageProvider)),
);

final socialSignInProvider = Provider<SocialSignIn>(
  (ref) => PlatformSocialSignIn(ref.watch(appConfigProvider)),
);
