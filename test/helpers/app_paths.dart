import 'dart:io';

import 'package:xclient/common/path.dart';

/// Разрешает каждый каталог, который [appPath] отдаёт в [root].
Future<void> useAppPaths(Directory root) {
  Future<Directory> resolve() async => root;
  AppPath.supportDirectory = resolve;
  AppPath.temporaryDirectory = resolve;
  AppPath.cacheDirectory = resolve;
  AppPath.downloadDirectory = resolve;
  return appPath.rebind();
}
