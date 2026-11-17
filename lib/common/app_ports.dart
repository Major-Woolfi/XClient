import 'dart:ui' show Brightness, Color;

import 'package:xclient/common/provider_reader.dart';
import 'package:xclient/models/models.dart';

abstract interface class WindowPort {
  Future<WindowProps?> captureNormalGeometry(WindowProps current);

  /// Возвращает непрозрачность, при которой боковая панель сохраняет свой цвет поверх фона,
  /// который теперь отрисован за контентом, или null, если фон не рисуется.
  Future<double?> setBlur({
    required bool enabled,
    required Brightness brightness,
    required Color tint,
  });

  Future<void> show();

  Future<void> hide();

  Future<void> toggle();

  Future<void> close();

  void forceExit();
}

abstract interface class TrayPort {
  Future<void> shutdown();

  Future<void> update({
    required TrayState trayState,
    required Traffic traffic,
    required ProviderReader read,
  });
}

abstract interface class NavigationPort {
  List<NavigationItem> getItems({bool openLogs, bool hasProxies});
}

WindowPort? windowPort;
TrayPort? trayPort;
NavigationPort? navigationPort;
