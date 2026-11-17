import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:xclient/common/boot_record.dart';
import 'package:xclient/plugins/app.dart';

/// Информация о платформе и устройстве.
class SystemInfo {
  static SystemInfo? _instance;

  bool _isTV = false;

  SystemInfo._internal();

  factory SystemInfo() {
    _instance ??= SystemInfo._internal();
    return _instance!;
  }

  bool get isDesktop => isWindows || isMacOS || isLinux;

  bool get isWindows => Platform.isWindows;

  bool get isMacOS => Platform.isMacOS;

  bool get isAndroid => Platform.isAndroid;

  bool get isLinux => Platform.isLinux;

  bool get isTV => _isTV;

  /// Возвращает версию ОС (major version для desktop, sdkInt для Android),
  /// или 0 если определить не удалось.
  Future<int> init() async {
    final BaseDeviceInfo deviceInfo;
    try {
      deviceInfo = await DeviceInfoPlugin().deviceInfo;
    } on RangeError {
      if (isWindows) return 0;
      rethrow;
    }
    _isTV = switch (deviceInfo) {
      AndroidDeviceInfo(:final systemFeatures) => systemFeatures.any(
        const {
          'android.hardware.type.television',
          'android.software.leanback',
        }.contains,
      ),
      _ => false,
    };
    return switch (Platform.operatingSystem) {
      'macos' => (deviceInfo as MacOsDeviceInfo).majorVersion,
      'android' => (deviceInfo as AndroidDeviceInfo).version.sdkInt,
      'windows' => (deviceInfo as WindowsDeviceInfo).majorVersion,
      String() => 0,
    };
  }

  /// Информация о последнем завершении приложения (Android only).
  Future<AppExitInfo?> lastExitInfo() async {
    if (!isAndroid) return null;
    return app?.getLastExitInfo();
  }

  bool get isAppImage =>
      isLinux && Platform.environment.containsKey('APPIMAGE');
}

final systemInfo = SystemInfo();
