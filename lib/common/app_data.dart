import 'dart:io';

import 'package:xclient/common/common.dart';
import 'package:xclient/database/database.dart';
import 'package:xclient/enum/enum.dart';

Future<void> clearAppData() async {
  await preferences.clearPreferences();
  try {
    await database.close();
  } catch (error) {
    // Drift пробрасывает неудачное открытие из close; этот файл всё равно нужно удалить.
    commonPrint.log(
      'close database failed: $error',
      logLevel: LogLevel.warning,
    );
  }
  await File(await appPath.databasePath).safeDelete(recursive: true);
  await Directory(await appPath.profilesPath).safeDelete(recursive: true);
}


