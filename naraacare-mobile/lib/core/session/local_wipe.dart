import 'dart:io';

import 'package:naraacare/core/storage/app_database.dart';
import 'package:naraacare/core/utils/logger.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Removes the signed-in user's data from this phone (doc 07 SEC-7.5, S15):
/// queued writes, local entries, cached status and the sync cursor in the
/// encrypted database, and downloaded reports / exports in the app's folder.
/// Runs on every sign-out (also when the server ended the session, e.g.
/// after an account deletion request), so the next person who signs in on
/// this phone never sees or sends someone else's data. Public reference data
/// (drink and food lists) is kept. Tokens are cleared by the session store.
Future<void> wipeLocalUserData(AppDatabase db) async {
  try {
    await db.transaction(() async {
      await db.delete(db.outboxItems).go();
      await db.delete(db.localEntries).go();
      await db.delete(db.cachedStatus).go();
      await db.delete(db.syncState).go();
    });
  } on Object catch (e) {
    log.info('local_wipe_db_failed', {'error': e.runtimeType.toString()});
  }
  try {
    final docs = await getApplicationDocumentsDirectory();
    for (final name in const ['reports', 'exports']) {
      final dir = Directory(p.join(docs.path, name));
      if (dir.existsSync()) await dir.delete(recursive: true);
    }
  } on Object catch (e) {
    log.info('local_wipe_files_failed', {'error': e.runtimeType.toString()});
  }
}
