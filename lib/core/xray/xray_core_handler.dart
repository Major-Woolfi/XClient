import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:xclient/common/common.dart';
import 'package:xclient/core/core.dart';
import 'package:xclient/enum/enum.dart';
import 'package:xclient/models/models.dart';

/// Обработчик ядра XRay: управляет бинарным процессом Xray-core и JSON-конфигом.
///
/// В отличие от Clash.Meta, который предоставляет API вызовов методов, Xray-core
/// управляется через JSON-конфигурационный файл и его локальный API (stat, log, reverse и т.д.).
/// Этот обработчик переводит общие вызовы [CoreHandlerInterface] в операции XRay:
/// запись JSON-конфига, запуск/остановку процесса, запросы к локальному API.
class XRayCoreHandler implements CoreHandlerInterface {
  static XRayCoreHandler? _instance;
  factory XRayCoreHandler() => _instance ??= XRayCoreHandler._internal();
  XRayCoreHandler._internal();

  static void resetInstance() {
    _instance = null;
  }

  Process? _process;
  String? _configPath;
  bool _connected = false;

  /// Путь к Xray-core бинарнику.
  Future<String?> get _binaryPath async {
    final version = await coreBinaryManager.getActiveVersion();
    return coreBinaryManager.getBinaryPath(CoreType.xray, version);
  }

  /// Домашняя директория Xray (где лежит config.json и geo файлы).
  Future<String> get _homeDir async {
    final home = await appPath.homeDirPath;
    final dir = Directory(p.join(home, 'xray'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }

  @override
  Future<CoreLifecycleResult> start() async {
    if (_connected) {
      return const CoreLifecycleResult(
        revision: 0,
        outcome: CoreLifecycleOutcome.coalesced,
      );
    }

    final binaryPath = await _binaryPath;
    if (binaryPath == null || !await File(binaryPath).exists()) {
      throw StateError('Xray-core binary not found. Install it first.');
    }

    final homeDir = await _homeDir;
    _configPath = p.join(homeDir, 'config.json');

    // Запись конфига по умолчанию, если его нет
    if (!await File(_configPath!).exists()) {
      await _writeDefaultConfig();
    }

    // Запуск процесса Xray
    try {
      _process = await Process.start(
        binaryPath,
        ['-config', _configPath!],
        workingDirectory: homeDir,
        mode: ProcessStartMode.normal,
      );

      _process!.stdout.listen((_) {});
      _process!.stderr.listen((data) {
        final error = utf8.decode(data);
        if (error.isNotEmpty) {
          commonPrint.log(
            'Xray stderr: $error',
            logLevel: LogLevel.warning,
          );
        }
      });

      _process!.exitCode.then((code) {
        _connected = false;
      });

      // Даём Xray время на запуск
      await Future.delayed(const Duration(seconds: 2));

      _connected = true;

      return const CoreLifecycleResult(
        revision: 0,
        outcome: CoreLifecycleOutcome.applied,
      );
    } catch (e) {
      _connected = false;
      throw StateError('Failed to start Xray-core: $e');
    }
  }

  @override
  Future<CoreLifecycleResult> restart() async {
    await stop();
    return start();
  }

  @override
  Future<CoreLifecycleResult> stop() async {
    if (!_connected) {
      return const CoreLifecycleResult(
        revision: 0,
        outcome: CoreLifecycleOutcome.coalesced,
      );
    }

    try {
      _process?.kill();
      await _process?.exitCode.timeout(const Duration(seconds: 3));
    } catch (_) {
      _process?.kill();
    }

    _connected = false;
    _process = null;

    return const CoreLifecycleResult(
      revision: 0,
      outcome: CoreLifecycleOutcome.applied,
    );
  }

  @override
  Future<CoreLifecycleResult> close() async {
    return stop();
  }

  @override
  Future<Object?> invokeMethod({
    required CoreMethod method,
    Object? arguments,
    Duration? timeout,
  }) async {
    if (!_connected) {
      throw CoreMethodException(
        code: 'core_unavailable',
        message: 'Xray-core is not connected for ${method.wireName}',
      );
    }

    switch (method) {
      case CoreMethod.coreInit:
        return _handleInit(arguments);
      case CoreMethod.coreInitialized:
        return _connected;
      case CoreMethod.coreGc:
        return null;
      case CoreMethod.coreMemory:
        return _getMemoryStats();
      case CoreMethod.configSetup:
        return _handleConfigSetup(arguments);
      case CoreMethod.configUpdate:
        return _handleConfigUpdate(arguments);
      case CoreMethod.configValidate:
        return _handleConfigValidate(arguments);
      case CoreMethod.configRead:
        return _handleConfigRead(arguments);
      case CoreMethod.profileBase:
        return _handleProfileBase();
      case CoreMethod.profileOutbounds:
        return _handleProfileOutbounds();
      case CoreMethod.profileBuild:
        return _handleProfileBuild(arguments);
      case CoreMethod.proxyList:
        return _handleProxyList();
      case CoreMethod.proxySelect:
        return _handleProxySelect(arguments);
      case CoreMethod.proxyTestDelay:
        return _handleProxyTestDelay(arguments);
      case CoreMethod.shareLinkEncode:
        return _handleShareLinkEncode(arguments);
      case CoreMethod.shareLinkDecode:
        return _handleShareLinkDecode(arguments);
      case CoreMethod.trafficCurrent:
        return _getTraffic(false);
      case CoreMethod.trafficTotal:
        return _getTraffic(true);
      case CoreMethod.connectionList:
        return _getConnections();
      case CoreMethod.connectionClose:
        return _closeConnection(arguments);
      case CoreMethod.connectionCloseAll:
        return _closeAllConnections();
      case CoreMethod.listenerStart:
      case CoreMethod.listenerStop:
        return null;
      default:
        throw UnimplementedError(
          'Xray-core does not support method ${method.wireName}',
        );
    }
  }

  // ---- Required interface methods ----

  @override
  Future<void> init(InitParams params) async {
    await _handleInit(params.toJson());
  }

  @override
  Future<bool> get isInit => Future.value(_connected);

  @override
  Future<void> forceGc() async {}

  @override
  Future<CoreMemoryStats> getMemoryStats() async {
    final mem = await _getMemoryStats() as Map<String, dynamic>;
    return CoreMemoryStats(
      rss: (mem['rss'] as num?)?.toInt() ?? 0,
      heapInuse: (mem['heap-inuse'] as num?)?.toInt() ?? 0,
      heapIdle: (mem['heap-idle'] as num?)?.toInt() ?? 0,
      stackInuse: (mem['stack-inuse'] as num?)?.toInt() ?? 0,
      runtimeOther: (mem['runtime-other'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<void> crash() async {
    _process?.kill();
    _connected = false;
  }

  @override
  Future<void> setupConfig(SetupParams params) async {
    await _writeConfigFromParams(params.toJson());
  }

  @override
  Future<void> updateConfig(UpdateParams params) async {
    await _writeConfigFromParams(params.toJson());
    await restart();
  }

  @override
  Future<String?> validateConfig(String path) async {
    if (!await File(path).exists()) {
      return 'Config file not found';
    }
    try {
      final content = await File(path).readAsString();
      jsonDecode(content);
      return null;
    } catch (e) {
      return 'Invalid JSON: $e';
    }
  }

  @override
  Future<String> decryptConfig(String path, String ageSecretKey) async {
    throw UnimplementedError('Xray-core does not support age-encrypted configs');
  }

  @override
  Future<Map<String, dynamic>> readConfig(String path) async {
    if (!await File(path).exists()) {
      return {};
    }
    final content = await File(path).readAsString();
    return jsonDecode(content);
  }

  @override
  Future<ProfileBase> getProfileBase(String path) async {
    return const ProfileBase(
      config: <String, dynamic>{},
      digest: '',
    );
  }

  @override
  Future<Map<String, dynamic>> getProfileOutbounds(String path) async {
    return <String, dynamic>{};
  }

  @override
  Future<String> buildProfile(SetupBase base) async {
    return '{}';
  }

  @override
  Future<void> clearEffect(int profileId) async {}

  @override
  Future<ProxiesData> getProxies() async {
    final configPath = _configPath;
    if (configPath == null) {
      return const ProxiesData(proxies: <String, dynamic>{}, all: <String>[]);
    }
    final file = File(configPath);
    if (!await file.exists()) {
      return const ProxiesData(proxies: <String, dynamic>{}, all: <String>[]);
    }
    try {
      final content = await file.readAsString();
      final decoded = jsonDecode(content) as Map<String, dynamic>;
      final outbounds = decoded['outbounds'] as List?;
      if (outbounds == null) {
        return const ProxiesData(proxies: <String, dynamic>{}, all: <String>[]);
      }
      final proxies = <String, dynamic>{};
      final all = <String>[];
      for (final outbound in outbounds) {
        if (outbound is! Map) continue;
        final tag = outbound['tag'] as String?;
        if (tag == null || tag.isEmpty) continue;
        final protocol = outbound['protocol'] as String? ?? 'unknown';
        final settings = outbound['settings'] as Map<String, dynamic>? ?? {};
        proxies[tag] = {
          'name': tag,
          'type': protocol,
          'protocol': protocol,
          'tag': tag,
          'settings': settings,
        };
        all.add(tag);
      }
      return ProxiesData(proxies: proxies, all: all);
    } catch (_) {
      return const ProxiesData(proxies: <String, dynamic>{}, all: <String>[]);
    }
  }

  @override
  Future<ChangeProxyResult> changeProxy(ChangeProxyParams params) async {
    // XRay не поддерживает живое переключение прокси без перезагрузки конфига.
    // Пользователь должен отредактировать конфиг XRay и перезапустить ядро.
    return const ChangeProxyResult(
      message: 'XRay core: change proxy via config edit and restart',
      changed: false,
    );
  }

  @override
  Future<Map<String, dynamic>?> getProxyDefinition(String name) async {
    final configPath = _configPath;
    if (configPath == null) return null;
    final file = File(configPath);
    if (!await file.exists()) return null;
    try {
      final content = await file.readAsString();
      final decoded = jsonDecode(content) as Map<String, dynamic>;
      final outbounds = decoded['outbounds'] as List?;
      if (outbounds == null) return null;
      for (final outbound in outbounds) {
        if (outbound is Map && outbound['tag'] == name) {
          return Map<String, dynamic>.from(outbound);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Delay> testDelay(TestDelayParams params) async {
    return const Delay(name: '', url: '', value: -1);
  }

  @override
  Future<Map<int, String>> validateProxies(
    List<Map<String, dynamic>> proxies,
  ) async {
    return <int, String>{};
  }

  @override
  Future<List<Map<String, dynamic>>> convertProxies(String path) async {
    return <Map<String, dynamic>>[];
  }

  @override
  Future<List<String>> encodeShareLinks(
    List<Map<String, dynamic>> proxies,
  ) async {
    return coreController.encodeXrayLinks(proxies);
  }

  @override
  Future<List<List<Map<String, dynamic>>>> decodeShareLinks(
    List<String> lines,
  ) async {
    return coreController.decodeXrayLinks(lines);
  }

  @override
  Future<Map<int, String>> validateFilters(List<String> filters) async {
    return <int, String>{};
  }

  @override
  Future<List<ExternalProvider>> getExternalProviders() async {
    return <ExternalProvider>[];
  }

  @override
  Future<ExternalProvider?> getExternalProvider(String name) async {
    return null;
  }

  @override
  Future<void> updateExternalProvider(String name) async {}

  @override
  Future<void> sideLoadExternalProvider({
    required String providerName,
    required String data,
  }) async {}

  @override
  Future<String> dumpRuleSet(String path) async {
    return '';
  }

  @override
  Future<RuleSetInfo> compileRuleSet(String name, {String url = ''}) async {
    return (
      behavior: RuleProviderBehavior.domain,
      format: RuleProviderFormat.yaml,
    );
  }

  @override
  Future<void> updateGeoData(String type) async {}

  @override
  Future<Traffic> getTraffic(bool onlyProxy) async {
    return const Traffic(up: 0, down: 0);
  }

  @override
  Future<Traffic> getTotalTraffic(bool onlyProxy) async {
    return const Traffic(up: 0, down: 0);
  }

  @override
  Future<void> resetTraffic() async {}

  @override
  Future<List<TrackerInfo>> getConnections() async {
    return <TrackerInfo>[];
  }

  @override
  Future<int> getConnectionCount() async {
    return 0;
  }

  @override
  Future<void> closeConnection(String id) async {}

  @override
  Future<void> closeConnections() async {}

  @override
  Future<void> resetConnections() async {}

  @override
  Future<void> clearDnsCache() async {}

  @override
  Future<void> reportNetworkChange() async {}

  @override
  Future<void> startLog() async {}

  @override
  Future<void> stopLog() async {}

  @override
  Future<void> startListener() async {}

  @override
  Future<void> stopListener() async {}

  @override
  Future<RouteSnapshot> watchRoute(bool watch) async {
    return const RouteSnapshot(coreEpoch: 0, routeVersion: 0);
  }

  @override
  Future<RouteCheck> checkRoutes(CheckRoutesParams params) async {
    return const RouteCheck();
  }

  @override
  Future<OutboundIpResult> outboundIp(OutboundIpParams params) async {
    return const OutboundIpResult(url: '', body: '', delay: 0, chains: <String>[], nodeHits: <RouteHit>[]);
  }

  @override
  Future<List<ServiceCheckItem>> serviceCheck(ServiceCheckParams params) async {
    return <ServiceCheckItem>[];
  }

  @override
  Future<MitmCertificate?> getMitmCertificate() async {
    return null;
  }

  @override
  Future<MitmCertificate> generateMitmCertificate() async {
    throw UnimplementedError('Xray-core does not support MITM');
  }

  @override
  Future<Map<MitmList, Map<int, String>>> validateMitm(MitmRules rules) async {
    return <MitmList, Map<int, String>>{};
  }

  @override
  Future<String> issueMitmCertificate(String host) async {
    throw UnimplementedError('Xray-core does not support MITM');
  }

  @override
  Future<MitmExchangeList> getMitmExchanges(String connectionId) async {
    return const MitmExchangeList(exchanges: <MitmExchangeSummary>[]);
  }

  @override
  Future<MitmExchange?> getMitmExchange(int id) async {
    return null;
  }

  @override
  Future<MitmBody?> getMitmBody(int id, {required bool response}) async {
    return null;
  }

  @override
  Future<MitmScriptOutput> runMitmScript(String name) async {
    throw UnimplementedError('Xray-core does not support MITM scripts');
  }

  // ---- Private handlers ----

  Future<Object?> _handleInit(Object? arguments) async {
    final params = arguments as Map<String, dynamic>?;
    final homeDir = params?['homeDir'] as String?;
    if (homeDir != null) {
      await _ensureGeoFiles(homeDir);
    }
    _connected = true;
    return null;
  }

  Future<Object?> _handleConfigSetup(Object? arguments) async {
    final params = arguments as Map<String, dynamic>?;
    if (params == null) return null;
    await _writeConfigFromParams(params);
    return null;
  }

  Future<Object?> _handleConfigUpdate(Object? arguments) async {
    final params = arguments as Map<String, dynamic>?;
    if (params == null) return null;
    await _writeConfigFromParams(params);
    await restart();
    return null;
  }

  Future<Object?> _handleConfigValidate(Object? arguments) async {
    final args = arguments as Map<String, dynamic>?;
    final path = args?['path'] as String?;
    if (path == null || !await File(path).exists()) {
      return 'Config file not found';
    }
    try {
      final content = await File(path).readAsString();
      jsonDecode(content);
      return null;
    } catch (e) {
      return 'Invalid JSON: $e';
    }
  }

  Future<Object?> _handleConfigRead(Object? arguments) async {
    final args = arguments as Map<String, dynamic>?;
    final path = args?['path'] as String?;
    if (path == null || !await File(path).exists()) {
      return {};
    }
    final content = await File(path).readAsString();
    return jsonDecode(content);
  }

  Future<Object?> _handleProfileBase() async {
    return {
      'proxies': <Map<String, dynamic>>[],
      'proxyGroups': <Map<String, dynamic>>[],
      'rules': <Map<String, dynamic>>[],
      'matchRules': <Map<String, dynamic>>[],
      'sha256': '',
    };
  }

  Future<Object?> _handleProfileOutbounds() async {
    return <Map<String, dynamic>>[];
  }

  Future<Object?> _handleProfileBuild(Object? arguments) async {
    return '{}';
  }

  Future<Object?> _handleProxyList() async {
    return {
      'proxies': <Map<String, dynamic>>[],
      'groups': <Map<String, dynamic>>[],
    };
  }

  Future<Object?> _handleProxySelect(Object? arguments) async {
    return {
      'changed': false,
      'selected': '',
    };
  }

  Future<Object?> _handleProxyTestDelay(Object? arguments) async {
    return {
      'delay': -1,
      'alive': false,
    };
  }

  Future<Object?> _handleShareLinkEncode(Object? arguments) async {
    final proxies = arguments as List<Map<String, dynamic>>?;
    if (proxies == null || proxies.isEmpty) return <String>[];
    return coreController.encodeXrayLinks(proxies);
  }

  Future<Object?> _handleShareLinkDecode(Object? arguments) async {
    final lines = arguments as List<String>?;
    if (lines == null || lines.isEmpty) return <List<Map<String, dynamic>>>[];
    return coreController.decodeXrayLinks(lines);
  }

  // ---- Config writing ----

  Future<void> _writeDefaultConfig() async {
    final config = {
      'log': {
        'loglevel': 'warning',
      },
      'inbounds': [
        {
          'port': 10808,
          'listen': '127.0.0.1',
          'protocol': 'socks',
          'settings': {},
        },
        {
          'port': 10809,
          'listen': '127.0.0.1',
          'protocol': 'http',
          'settings': {},
        },
      ],
      'outbounds': [
        {
          'protocol': 'freedom',
          'tag': 'direct',
        },
        {
          'protocol': 'blackhole',
          'tag': 'blocked',
        },
      ],
      'routing': {
        'rules': [
          {
            'type': 'field',
            'ip': ['geoip:private'],
            'outboundTag': 'direct',
          },
        ],
      },
    };
    await File(_configPath!).writeAsString(
      const JsonEncoder.withIndent('  ').convert(config),
    );
  }

  Future<void> _writeConfigFromParams(Map<String, dynamic> params) async {
    final configPath = _configPath ??= p.join(await _homeDir, 'config.json');
    final config = <String, dynamic>{};

    for (final key in [
      'log', 'dns', 'inbounds', 'outbounds', 'routing',
      'transport', 'policy',
    ]) {
      if (params.containsKey(key)) {
        config[key] = params[key];
      }
    }

    await File(configPath).writeAsString(
      const JsonEncoder.withIndent('  ').convert(config),
    );
  }

  Future<void> _ensureGeoFiles(String homeDir) async {
    final geoFiles = ['geoip.dat', 'geosite.dat'];
    for (final name in geoFiles) {
      final file = File(p.join(homeDir, name));
      if (!await file.exists()) {
        try {
          final data = await rootBundle.load('assets/data/$name');
          await file.writeAsBytes(
            data.buffer.asUint8List(),
            flush: true,
          );
        } catch (_) {
          // Ассет может не существовать; XRay загрузит его по требованию
        }
      }
    }
  }

  Future<Object?> _getMemoryStats() async {
    return {
      'rss': 0,
      'heap-inuse': 0,
      'heap-idle': 0,
      'stack-inuse': 0,
      'runtime-other': 0,
    };
  }

  Future<Object?> _getTraffic(bool onlyProxy) async {
    return {
      'upload': 0,
      'download': 0,
      'total': 0,
    };
  }

  Future<Object?> _getConnections() async {
    return <Map<String, dynamic>>[];
  }

  Future<Object?> _closeConnection(Object? arguments) async {
    return null;
  }

  Future<Object?> _closeAllConnections() async {
    return null;
  }
}
