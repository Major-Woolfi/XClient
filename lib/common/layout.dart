import 'dart:math';
import 'dart:ui' show Size;

import 'package:xclient/enum/enum.dart';
import 'package:xclient/ui/ui.dart';
import 'package:flutter/widgets.dart' show BuildContext;

import 'constant.dart';

double getWindowHeaderHeight({required bool isDesktop, required bool isMacOS}) {
  if (!isDesktop) return 0;
  return isMacOS ? 28 : 32;
}

/// Windows 11 рисует кнопки заголовка шириной 46 над 32-пиксельной панелью заголовка.
const captionButtonWidth = 46.0;

/// Пин не является кнопкой заголовка: он удерживает круглую Material-кнопку в
/// квадратном слоте высотой с панель, с обычным размером иконки.
const pinIconSize = 16.0;

Size getCaptionButtonSize(double headerHeight) =>
    Size(captionButtonWidth, headerHeight);

bool showsWindowHeader({
  required bool isDesktop,
  required bool isMacOS,
  required int version,
  required bool isMobileView,
}) {
  if (!isDesktop) return false;
  return !(isMacOS && (version <= 10 || !isMobileView));
}

ViewMode getViewMode(double viewWidth) {
  if (viewWidth <= maxMobileWidth) return ViewMode.mobile;
  if (viewWidth <= maxLaptopWidth) return ViewMode.laptop;
  return ViewMode.desktop;
}

/// Развёрнутая боковая панель в диапазоне ноутбука оставила бы контент уже,
/// чем мобильный макет на одном breakpoint ниже, поэтому метки ждут десктоп.
bool canExpandSidebar(ViewMode viewMode) => viewMode == ViewMode.desktop;

/// Измерено на macOS 27, светофоры охватывают 9..69 от левого края
/// скрытой 32-пиксельной панели заголовка; macOS 10 сохраняет свою панель заголовка.
const macOSTrafficLightsArea = Size(78, 32);

Size windowControlsOverSidebar({required bool isMacOS, required int version}) {
  return isMacOS && version > 10 ? macOSTrafficLightsArea : Size.zero;
}

/// Мобильное вид хранит светофоры в панели заголовка окна, поэтому только страница,
/// заполняющая более широкое окно, встречает их.
Size windowControlsOverPage({
  required bool isMacOS,
  required int version,
  required bool isMobileView,
}) {
  if (isMobileView) return Size.zero;
  return windowControlsOverSidebar(isMacOS: isMacOS, version: version);
}

int getProxiesColumns(double viewWidth, ProxiesLayout proxiesLayout) {
  final columns = max((viewWidth / 250).ceil(), 2);
  return switch (proxiesLayout) {
    ProxiesLayout.tight => columns + 1,
    ProxiesLayout.standard => columns,
    ProxiesLayout.loose => columns - 1,
  };
}

double cardSpacingOf(BuildContext context, ViewMode viewMode) =>
    switch (viewMode) {
      ViewMode.mobile => 8.0,
      ViewMode.laptop => 12.0,
      ViewMode.desktop => 16.0,
    }.mAp(context);

const profileItemMinWidth = 300.0;
const _profilesMaxColumns = 3;

int getProfilesColumns(
  double viewWidth, {
  double spacing = 0,
  double minItemWidth = profileItemMinWidth,
}) {
  final columns = (viewWidth + spacing) / (minItemWidth + spacing);
  return columns.floor().clamp(1, _profilesMaxColumns);
}


