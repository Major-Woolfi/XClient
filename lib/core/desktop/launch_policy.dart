import 'dart:io';

import 'package:xclient/core/desktop/helper_client.dart';
import 'package:xclient/core/desktop/model.dart';
import 'package:win32_registry/win32_registry.dart';

/// CreateProcess возвращает эти коды, когда политику (а не файл) запретила образ:
/// ERROR_VIRUS_INFECTED, ERROR_INVALID_IMAGE_HASH, ERROR_ACCESS_DISABLED_BY_POLICY.
const policyBlockedOsErrors = {225, 577, 1260};

enum SmartAppControlState { off, on, evaluation, unknown }

typedef SmartAppControlStateReader = SmartAppControlState Function();

/// Переопределяется тестами; реальный читатель требует реестр Windows.
SmartAppControlStateReader smartAppControlStateReader =
    readSmartAppControlState;

SmartAppControlState readSmartAppControlState() {
  if (!Platform.isWindows) {
    return SmartAppControlState.unknown;
  }
  try {
    final key = LOCAL_MACHINE.open(
      r'SYSTEM\CurrentControlSet\Control\CI\Policy',
    );
    try {
      return switch (key.getInt('VerifiedAndReputablePolicyState')) {
        0 => SmartAppControlState.off,
        1 => SmartAppControlState.on,
        2 => SmartAppControlState.evaluation,
        _ => SmartAppControlState.unknown,
      };
    } finally {
      key.close();
    }
  } catch (_) {
    return SmartAppControlState.unknown;
  }
}

/// Код ошибки ОС за неудачный запуск ядра,无论 Helper породил ядро
/// (код лежит в деталях ответа, старые Helper — только в сообщении)
/// или приложение (dart:io хранит её на исключении).
int? launchOsError(Object? error) {
  return switch (error) {
    DesktopCoreFailure(:final cause) => launchOsError(cause),
    ProcessException(:final errorCode) => errorCode == 0 ? null : errorCode,
    HelperException(code: 'processLaunchFailed') => _helperOsError(error),
    _ => null,
  };
}

bool isPolicyBlockedLaunch(Object? error) {
  return policyBlockedOsErrors.contains(launchOsError(error));
}

int? _helperOsError(HelperException error) {
  final details = error.details;
  if (details is Map && details['osError'] is int) {
    return details['osError'] as int;
  }
  final match = RegExp(r'os error (\d+)').firstMatch(error.message);
  return match == null ? null : int.tryParse(match.group(1)!);
}


