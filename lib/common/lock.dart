import 'dart:io';

import 'package:xclient/common/common.dart';
import 'package:xclient/enum/enum.dart';
import 'package:flutter/foundation.dart';

/// Не даёт двум процессам работать с одной директорией данных. Поднятие окна
/// запущенного приложения — задача платформы: повторное открытие LaunchServices,
/// активация GApplication или передача app_links в Windows-раннере.
class SingleInstanceLock {
  static SingleInstanceLock? _instance;
  RandomAccessFile? _accessFile;

  SingleInstanceLock._internal();

  factory SingleInstanceLock() {
    _instance ??= SingleInstanceLock._internal();
    return _instance!;
  }

  @visibleForTesting
  static Future<String> Function() resolvePath = () => appPath.lockFilePath;

  Future<bool> acquire() async {
    try {
      final lockFilePath = await resolvePath();
      final lockFile = File(lockFilePath);
      await lockFile.create();
      _accessFile = await lockFile.open(mode: FileMode.write);
      await _accessFile?.lock();
      return true;
    } catch (e) {
      commonPrint.log(
        'single instance lock acquire failed ${e.toString()}',
        logLevel: LogLevel.warning,
      );
      return false;
    }
  }

  @visibleForTesting
  Future<void> release() async {
    await _accessFile?.close();
    _accessFile = null;
  }
}

final singleInstanceLock = SingleInstanceLock();


