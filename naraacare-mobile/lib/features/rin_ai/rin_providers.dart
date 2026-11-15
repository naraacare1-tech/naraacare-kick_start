import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:naraacare/core/providers.dart';
import 'package:naraacare/features/rin_ai/data/rin_data.dart';

final rinApiProvider = Provider<RinApi>(
  (ref) => RinApi(ref.watch(apiClientProvider)),
);

final FutureProvider<RinUsage> rinUsageProvider =
    FutureProvider.autoDispose<RinUsage>(
      (ref) => ref.watch(rinApiProvider).usage(),
    );
