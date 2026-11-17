import 'package:xclient/common/common.dart';
import 'package:flutter/services.dart';

class BatteryOptimization {
  BatteryOptimization._();

  static final instance = BatteryOptimization._();

  static const _methodChannel = MethodChannel('$packageName/battery');
  static const _eventChannel = EventChannel(
    '$packageName/battery/optimization',
  );

  /// Текущий ответ при прослушивании, затем по каждому изменению. На Xiaomi
  /// следует режиму "Без ограничений" экономии батареи вместо списка разрешений.
  late final Stream<bool> onChanged = _eventChannel
      .receiveBroadcastStream()
      .map((event) => event as bool);

  /// Завершается, когда пользователь покидает страницу настроек; сам ответ
  /// приходит через [onChanged].
  Future<void> requestIgnore() {
    return _methodChannel.invokeMethod<void>('requestIgnoreOptimizations');
  }
}

final batteryOptimization = system.isAndroid
    ? BatteryOptimization.instance
    : null;
