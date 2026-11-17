import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:xclient/common/common.dart';
import 'package:xclient/core/core_type.dart';
import 'package:xclient/core/core_manager.dart';
import 'package:xclient/core/desktop/model.dart';
import 'package:xclient/core/interface.dart';
import 'package:xclient/core/lib.dart';
import 'package:xclient/core/method.dart';
import 'package:xclient/core/service.dart';
import 'package:xclient/core/spill.dart';
import 'package:xclient/core/xray/xray_link_codec.dart';
import 'package:xclient/enum/enum.dart';
import 'package:xclient/models/models.dart';
import 'package:xclient/plugins/app.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:path/path.dart';

/// Реестр реализаций ядер по типу.
///
/// Позволяет переключаться между Clash.Meta и Xray-core без пересборки приложения.
class CoreRegistry {
  static CoreRegistry? _instance;
  factory CoreRegistry() => _instance ??= CoreRegistry._internal();
  CoreRegistry._internal();

  final Map<CoreType, CoreHandlerInterface> _implementations = {};

  void register(CoreType type, CoreHandlerInterface implementation) {
    _implementations[type] = implementation;
  }

  CoreHandlerInterface? get(CoreType type) => _implementations[type];

  bool has(CoreType type) => _implementations.containsKey(type);
}

final coreRegistry = CoreRegistry();

/// Контроллер над активной реализацией [CoreHandlerInterface].
///
/// Все вызовы перенаправляются на реализацию, соответствующую текущему активному
/// ядру (Clash.Meta или Xray-core).
class CoreController {
  static CoreController? _instance;
  CoreHandlerInterface? _interface;

  factory CoreController() {
    return _instance ??= CoreController._();
  }

  CoreController._();

  @visibleForTesting
  factory CoreController.test(CoreHandlerInterface interface) {
    return _instance = CoreController._().._interface = interface;
  }

  @visibleForTesting
  CoreController.scoped(CoreHandlerInterface interface) {
    _interface = interface;
  }

  @visibleForTesting
  static void resetInstance() {
    _instance = null;
    _instance?._interface = null;
  }

  /// Возвращает реализацию для текущего активного типа ядра.
  CoreHandlerInterface get _active {
    if (_interface != null) return _interface!;
    final type = coreBinaryManager.activeCoreType;
    final impl = coreRegistry.get(type);
    if (impl != null) return impl;
    // Фолбэк: Android использует CoreLib, desktop — CoreService.
    return system.isAndroid ? coreLib! : coreService!;
  }

  static Future<void> ensureHomeDir() async {
    final homePath = await appPath.homeDirPath;
    final homeDir = Directory(homePath);
    final isExists = await homeDir.exists();
    if (!isExists) {
      await homeDir.create(recursive: true);
    }
    await system.grantHomeDirAccess(homePath);
  }

  static Future<void> initGeo() async {
    final homePath = await appPath.homeDirPath;
    const geoFileNameList = [MMDB, GEOIP, GEOSITE, ASN];
    try {
      for (final geoFileName in geoFileNameList) {
        final geoFile = File(join(homePath, geoFileName));
        final isExists = await geoFile.exists();
        if (isExists) {
          continue;
        }
        final asset = 'assets/data/$geoFileName';
        if (app case final app?) {
          await app.extractAsset(asset, geoFile.path);
          continue;
        }
        final data = await rootBundle.load(asset);
        final List<int> bytes = data.buffer.asUint8List();
        await geoFile.writeAsBytes(bytes, flush: true);
      }
    } catch (e) {
      commonPrint.log(
        'Failed to initialize geo data: $e',
        logLevel: LogLevel.error,
      );
      rethrow;
    }
  }

  Future<void> initCore(int version) async {
    await ensureHomeDir();
    await initGeo();
    final homeDirPath = await appPath.homeDirPath;
    await _active.init(InitParams(homeDir: homeDirPath, version: version));
  }

  /// Переключить активное ядро. Вызывается из CoreBinaryManager после установки.
  Future<void> switchTo(CoreType type) async {
    final impl = coreRegistry.get(type);
    if (impl == null) {
      throw StateError('No implementation registered for $type');
    }
    _interface = impl;
    await impl.init(InitParams(
      homeDir: await appPath.homeDirPath,
      version: 0,
    ));
  }

  /// Тип текущего активного ядра.
  Future<CoreType> get activeCoreType => coreBinaryManager.getSavedCoreType();

  /// Активный менеджер бинарников ядер (версии, скачивание, переключение).
  CoreBinaryManager get coreBinaryManagerInstance => coreBinaryManager;

  /// Декодировать список ссылок XRay (работает независимо от активного ядра).
  Future<List<List<Map<String, dynamic>>>> decodeXrayLinks(
    List<String> lines,
  ) async {
    if (lines.isEmpty) {
      return Future.value(const []);
    }
    final result = <List<Map<String, dynamic>>>[];
    for (final line in lines) {
      final link = decodeXrayLink(line);
      if (link.type == XrayLinkType.unknown) {
        result.add(const []);
        continue;
      }
      result.add([xrayLinkToOutbound(link)]);
    }
    return result;
  }

  /// Закодировать список прокси в ссылки XRay.
  Future<List<String>> encodeXrayLinks(List<Map<String, dynamic>> proxies) async {
    if (proxies.isEmpty) {
      return Future.value(const []);
    }
    final result = <String>[];
    for (final proxy in proxies) {
      final typeStr = proxy['type'] as String? ?? '';
      final linkType = switch (typeStr) {
        'vmess' => XrayLinkType.vmess,
        'vless' => XrayLinkType.vless,
        'trojan' => XrayLinkType.trojan,
        'shadowsocks' => XrayLinkType.shadowsocks,
        _ => XrayLinkType.unknown,
      };
      if (linkType == XrayLinkType.unknown) {
        result.add('');
        continue;
      }
      final link = XrayLink.fromComponents(
        type: linkType,
        address: proxy['address'] as String? ?? '',
        port: (proxy['port'] as num?)?.toInt() ?? 0,
        tag: proxy['tag'] as String?,
        uuid: proxy['uuid'] as String?,
        password: proxy['password'] as String?,
        method: proxy['method'] as String?,
        network: proxy['network'] as String?,
        security: proxy['security'] as String?,
        sni: proxy['sni'] as String?,
        fingerprint: proxy['fingerprint'] as String?,
        alpn: proxy['alpn'] as String?,
        publicKey: proxy['publicKey'] as String?,
        shortId: proxy['shortId'] as String?,
        spiderX: proxy['spiderX'] as String?,
        flow: proxy['flow'] as String?,
        udp: proxy['udp'] as bool?,
        grpc: proxy['grpc'] as bool?,
        grpcServiceName: proxy['grpcServiceName'] as String?,
        wsPath: proxy['wsPath'] as String?,
        wsHeaders: proxy['wsHeaders'] != null
            ? Map<String, String>.from(proxy['wsHeaders'] as Map)
            : null,
        altSni: proxy['altSni'] as String?,
      );
      result.add(link.toLink());
    }
    return result;
  }

  Future<CoreLifecycleResult> start() => _active.start();

  Future<CoreLifecycleResult> restart() => _active.restart();

  Future<CoreLifecycleResult> stop() => _active.stop();

  Future<CoreLifecycleResult> close() => _active.close();

  Future<Object?> invokeMethod({
    required CoreMethod method,
    Object? arguments,
    Duration? timeout,
  }) => _active.invokeMethod(method: method, arguments: arguments, timeout: timeout);

  Future<void> init(InitParams params) => _active.init(params);

  Future<bool> get isInit => _active.isInit;

  Future<void> forceGc() => _active.forceGc();

  Future<CoreMemoryStats> getMemoryStats() => _active.getMemoryStats();

  Future<void> crash() => _active.crash();

  Future<void> setupConfig({
    required SetupParams params,
    Future<void> Function()? preloadInvoke,
  }) async {
    if (preloadInvoke == null) {
      return _active.setupConfig(params);
    }
    await (_active.setupConfig(params), preloadInvoke()).wait;
  }

  Future<void> updateConfig(UpdateParams params) => _active.updateConfig(params);

  Future<String?> validateConfig(String path) => _active.validateConfig(path);

  Future<String> decryptConfig(String path, String ageSecretKey) =>
      _active.decryptConfig(path, ageSecretKey);

  Future<Map<String, dynamic>> readConfig(String path) =>
      _active.readConfig(path);

  Future<ProfileBase> getProfileBase(String path) =>
      _active.getProfileBase(path);

  Future<Map<String, dynamic>> getProfileOutbounds(String path) =>
      _active.getProfileOutbounds(path);

  Future<void> clearEffect(int profileId) => _active.clearEffect(profileId);

  Future<ProxiesData> getProxies() => _active.getProxies();

  Future<ChangeProxyResult> changeProxy(ChangeProxyParams params) =>
      _active.changeProxy(params);

  Future<Map<String, dynamic>?> getProxyDefinition(String name) =>
      _active.getProxyDefinition(name);

  Future<Delay> testDelay(TestDelayParams params) => _active.testDelay(params);

  Future<Map<int, String>> validateProxies(List<Map<String, dynamic>> proxies) =>
      _active.validateProxies(proxies);

  Future<List<Map<String, dynamic>>> convertProxies(String path) =>
      _active.convertProxies(path);

  Future<List<String>> encodeShareLinks(List<Map<String, dynamic>> proxies) =>
      _active.encodeShareLinks(proxies);

  Future<List<List<Map<String, dynamic>>>> decodeShareLinks(
    List<String> lines,
  ) =>
      _active.decodeShareLinks(lines);

  Future<Map<int, String>> validateFilters(List<String> filters) =>
      _active.validateFilters(filters);

  Future<List<ExternalProvider>> getExternalProviders() =>
      _active.getExternalProviders();

  Future<ExternalProvider?> getExternalProvider(String name) =>
      _active.getExternalProvider(name);

  Future<void> updateExternalProvider(String name) =>
      _active.updateExternalProvider(name);

  Future<void> sideLoadExternalProvider({
    required String providerName,
    required String data,
  }) =>
      _active.sideLoadExternalProvider(
        providerName: providerName,
        data: data,
      );

  Future<String> dumpRuleSet(String path) => _active.dumpRuleSet(path);

  Future<RuleSetInfo> compileRuleSet(String name, {String url = ''}) =>
      _active.compileRuleSet(name, url: url);

  Future<void> updateGeoData(String type) => _active.updateGeoData(type);

  Future<Traffic> getTraffic(bool onlyProxy) => _active.getTraffic(onlyProxy);

  Future<Traffic> getTotalTraffic(bool onlyProxy) =>
      _active.getTotalTraffic(onlyProxy);

  Future<void> resetTraffic() => _active.resetTraffic();

  Future<List<TrackerInfo>> getConnections() => _active.getConnections();

  Future<int> getConnectionCount() => _active.getConnectionCount();

  Future<void> closeConnection(String id) => _active.closeConnection(id);

  Future<void> closeConnections() => _active.closeConnections();

  Future<void> resetConnections() => _active.resetConnections();

  Future<void> clearDnsCache() => _active.clearDnsCache();

  Future<void> reportNetworkChange() => _active.reportNetworkChange();

  Future<void> startLog() => _active.startLog();

  Future<void> stopLog() => _active.stopLog();

  Future<void> startListener() => _active.startListener();

  Future<void> stopListener() => _active.stopListener();

  Future<RouteSnapshot> watchRoute(bool watch) => _active.watchRoute(watch);

  Future<RouteCheck> checkRoutes(CheckRoutesParams params) =>
      _active.checkRoutes(params);

  Future<OutboundIpResult> outboundIp(OutboundIpParams params) =>
      _active.outboundIp(params);

  Future<List<ServiceCheckItem>> serviceCheck(ServiceCheckParams params) =>
      _active.serviceCheck(params);

  Future<MitmCertificate?> getMitmCertificate() => _active.getMitmCertificate();

  Future<MitmCertificate> generateMitmCertificate() =>
      _active.generateMitmCertificate();

  Future<Map<MitmList, Map<int, String>>> validateMitm(MitmRules rules) =>
      _active.validateMitm(rules);

  Future<String> issueMitmCertificate(String host) =>
      _active.issueMitmCertificate(host);

  Future<MitmExchangeList> getMitmExchanges(String connectionId) =>
      _active.getMitmExchanges(connectionId);

  Future<MitmExchange?> getMitmExchange(int id) =>
      _active.getMitmExchange(id);

  Future<MitmBody?> getMitmBody(int id, {required bool response}) =>
      _active.getMitmBody(id, response: response);

  Future<MitmScriptOutput> runMitmScript(String name) =>
      _active.runMitmScript(name);

  /// Определяет тип ядра по содержимому конфиг-файла и переключает ядро,
  /// если текущее не совпадает. Возвращает обнаруженный тип.
  Future<CoreType> detectAndSwitchCore(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return activeCoreType;
    }
    final content = await file.readAsString();
    final detected = _detectCoreType(content);
    final current = await activeCoreType;
    if (detected != current) {
      await switchTo(detected);
    }
    return detected;
  }

  CoreType _detectCoreType(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return CoreType.clash;
    // JSON-конфиги — это XRay.
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      try {
        jsonDecode(trimmed);
        return CoreType.xray;
      } catch (_) {
        return CoreType.clash;
      }
    }
    // YAML-базис: проверка ключей Clash vs XRay через CoreType.acceptsConfig.
    final clashScore = CoreType.clash.acceptsConfig(content) ? 1 : 0;
    final xrayScore = CoreType.xray.acceptsConfig(content) ? 1 : 0;
    if (xrayScore > clashScore) return CoreType.xray;
    return CoreType.clash;
  }

  /// Валидация профиля с автоматическим определением и переключением ядра.
  Future<String?> validateProfileWithAutoCore(
    String path, [
    String ageSecretKey = '',
  ]) async {
    await detectAndSwitchCore(path);
    return validateProfile(path, ageSecretKey);
  }

  /// Валидация конфига с автоматическим определением и переключением ядра.
  Future<String?> validateConfigWithAutoCore(String path) async {
    await detectAndSwitchCore(path);
    return validateConfig(path);
  }

  /// Конфиг, зашифрованный через age, перезаписывается на месте в plaintext, а
  /// список share-ссылок — в конфиг из его прокси.
  Future<String?> validateProfile(
    String path, [
    String ageSecretKey = '',
  ]) async {
    final file = File(path);
    if (await file.isAgeEncrypted) {
      if (ageSecretKey.isEmpty) {
        throw const AgeSecretKeyRequiredException();
      }
      await file.safeWriteAsString(
        await _active.decryptConfig(path, ageSecretKey),
      );
    }
    final issue = await _active.validateConfig(path);
    if (issue == null) {
      return null;
    }
    final List<Map<String, dynamic>> proxies;
    try {
      proxies = await _active.convertProxies(path);
    } on Exception {
      return issue;
    }
    if (proxies.isEmpty) {
      return issue;
    }
    await file.safeWriteAsString(await encodeYamlTask({'proxies': proxies}));
    return _active.validateConfig(path);
  }

  Future<String?> validateConfigWithData(List<int> data) async {
    final path = await appPath.tempFilePath;
    final file = File(path);
    await file.safeWriteAsBytes(data);
    try {
      return await _active.validateConfig(path);
    } finally {
      await file.safeDelete();
    }
  }

  Future<List<Group>> getProxiesGroups({
    required ProxiesSortType sortType,
    required DelayMap delayMap,
    required Map<String, String> selectedMap,
    required String defaultTestUrl,
  }) async {
    final proxiesData = await _active.getProxies();
    return toGroupsTask(
      ComputeGroupsState(
        proxiesData: proxiesData,
        sortType: sortType,
        delayMap: delayMap,
        selectedMap: selectedMap,
        defaultTestUrl: defaultTestUrl,
      ),
    );
  }

  Future<Map<String, dynamic>> readProfileConfig(int id) async {
    final path = await appPath.getProfilePath(id.toString());
    final data = await _active.readConfig(path);
    data['rules'] = data['rule'];
    data.remove('rule');
    return data;
  }

  Future<Map<String, dynamic>> getProfileOutboundsForProfile(int id) async {
    return _active.getProfileOutbounds(
      await appPath.getProfilePath(id.toString()),
    );
  }

  Future<String> buildProfile(SetupBase base) async {
    return readSpilledText(await _active.buildProfile(base));
  }

  Future<({ProfileBase base, String path})> getProfileBaseForProfile(int id) async {
    final path = await appPath.getProfilePath(id.toString());
    final base = await _active.getProfileBase(path);
    final config = Map<String, dynamic>.from(base.config)..remove('rule');
    return (base: base.copyWith(config: config), path: path);
  }
}

final coreController = CoreController();
