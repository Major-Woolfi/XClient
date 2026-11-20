import 'dart:io';

import 'package:xclient/common/common.dart';
import 'package:xclient/core/core_manager.dart';
import 'package:xclient/core/core_type.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../helpers/app_paths.dart';
import '../helpers/preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory home;
  late CoreBinaryManager manager;

  setUp(() async {
    home = Directory.systemTemp.createTempSync('core_binary_manager_test');
    await useAppPaths(home);
    await mockPreferences();
    CoreBinaryManager.resetInstance();
    manager = CoreBinaryManager();
  });

  tearDown(() {
    CoreBinaryManager.resetInstance();
    home.deleteSync(recursive: true);
  });

  test('starts with the clash core and its default version', () async {
    expect(manager.activeCoreType, CoreType.clash);
    expect(await manager.getActiveVersion(), '1.19.33');
  });

  test('reads the saved core type from preferences', () async {
    expect(await manager.getSavedCoreType(), CoreType.clash);

    await mockPreferences({'active_core_type': 'xray'});
    expect(await manager.getSavedCoreType(), CoreType.xray);
  });

  test('setActiveCore stores the type and an explicit version', () async {
    await manager.setActiveCore(CoreType.xray, version: '1.9.0');

    expect(manager.activeCoreType, CoreType.xray);
    expect(await manager.getSavedCoreType(), CoreType.xray);
    expect(await manager.getActiveVersion(), '1.9.0');
  });

  test('setActiveCore falls back to the xray default version', () async {
    await manager.setActiveCore(CoreType.xray);

    expect(await manager.getActiveVersion(), '1.8.1');
  });

  test('reports empty installed and available lists', () async {
    expect(manager.getAvailableVersions(CoreType.clash), isEmpty);
    expect(manager.getInstalledVersions(CoreType.xray), isEmpty);
    expect(await manager.getLatestInstalledVersion(CoreType.xray), isNull);
    expect(await manager.getBinaryPath(CoreType.xray, '1.0.0'), isNull);
  });

  test('builds the active binary path under the cores directory', () async {
    final path = await manager.activeBinaryPath;
    expect(
      path,
      p.join(
        home.path,
        'cores',
        CoreType.clash.storageDir,
        '1.19.33',
        'XClientCore${appPath.executableExtension}',
      ),
    );
  });

  test('refuses to uninstall the active core version', () async {
    expect(await manager.uninstallCore(CoreType.clash, '1.19.33'), isFalse);
  });

  test('detects the core type from a share link', () {
    expect(manager.detectCoreTypeFromLink('vmess://x'), CoreType.xray);
    expect(manager.detectCoreTypeFromLink('clash://x'), CoreType.clash);
    expect(manager.detectCoreTypeFromLink('unknown://x'), CoreType.clash);
  });

  test('detects the core type from config contents', () {
    expect(
      manager.detectCoreTypeFromConfig('inbounds:\noutbounds:\n'),
      CoreType.xray,
    );
    expect(
      manager.detectCoreTypeFromConfig('port: 7890\nproxies:\n'),
      CoreType.clash,
    );
    expect(manager.detectCoreTypeFromConfig(''), CoreType.clash);
  });
}
