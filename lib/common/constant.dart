// ignore_for_file: constant_identifier_names

import 'dart:io';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:xclient/common/common.dart';
import 'package:xclient/enum/enum.dart';
import 'package:xclient/models/models.dart';
import 'package:flutter/widgets.dart';

const appName = 'XClient';
const appHelperService = 'XClientHelperService';
const coreManifestName = 'manifest.json';
const browserUa =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
const packageName = 'com.xclient';
final unixSocketPath = '/tmp/XClientSocket_${Random().nextInt(10000)}.sock';
final windowsPipeName = '\\\\.\\pipe\\XClientCore_${_randomPipeId()}';
const helperPort = 47890;
const helperPortKey =
    'SYSTEM\\CurrentControlSet\\Services\\$appHelperService\\Runtime';
const helperPortValue = 'Port';
const helperSocketPath = '/run/XClient/helper.sock';
const helperUnitPath = '/etc/systemd/system/XClient-helper.service';
const helperProtocolVersionHeader = 'x-XClient-helper-protocol';
final helperProtocolVersion = Platform.isWindows ? '8' : '6';
const maxTextScale = 1.4;
const minTextScale = 0.8;

const watchExecution = false;

const safeModeBuild = bool.fromEnvironment('SAFE_MODE');

/// В собранном ядре нет MITM, поэтому это выключено, пока не выйдет ядро с ним.
/// Not const, чтобы тесты покрывали оба состояния.
bool mitmFeature = const bool.fromEnvironment('FEATURE_MITM');

const disclaimerVersion = 1;

String _randomPipeId() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

/// Зависит от текстовых масштабов [context], поэтому вызывающий перестраивается при
/// изменении системного масштаба шрифта.
double systemTextScaleOf(BuildContext context) {
  MediaQuery.textScalerOf(context);
  return WidgetsBinding.instance.platformDispatcher.textScaleFactor;
}

/// Сколько миллисекунд ядро может потратить на один ручной тест задержки. Оно
/// тратит это дважды в худшем случае — один раз на очередь за слотом, один раз
/// на саму проверку — поэтому защита ниже должна длиться дольше двух самых длинных вариантов.
const delayTestTimeoutOptions = [500, 1000, 2000, 5000, 8000];

const defaultDelayTestTimeout = 8000;

const delayTestGuardDuration = Duration(seconds: 30);

const delayTimedOutValue = -1;

const probeTimeoutDuration = Duration(seconds: 10);

/// Переживает опрос выбора ядра раз в секунду (`routePollInterval` в
/// core/route.go), так что группы, выбирающиеся на соседних опросах, стоят одной
/// проверки маршрута.
const probeSettleDuration = Duration(milliseconds: 1500);

/// Охватывает загрузку конфига, чьи провайдеры, наборы правил и выбор url-тестов
/// Landing в течение нескольких секунд, поэтому выход, moving с каждым, стоит одной проверки больше.
const probeThrottleDuration = Duration(seconds: 5);

/// Покрывает старт, который двигает маршрут трижды за около 150 мс
/// (`proxied`, затем слушатели, затем Android TUN).
const probeMoveSettleDuration = Duration(milliseconds: 300);

const downloadTimeoutDuration = Duration(seconds: 20);

/// Здоровый источник отвечает в течение секунды; после этого аутбаунд считается нерабочим.
const outboundIpTimeoutDuration = Duration(seconds: 6);

/// Ядро может потратить таймаут метода дважды: один раз на очередь за слотом проверки,
/// один раз на запрос, прежде чем транспорт сочтётся не отвечающим.
/// [budgetFactor] покрывает методы, которые тратят его более одного раза.
Duration coreGuardFor(int timeout, {int budgetFactor = 2}) =>
    Duration(milliseconds: timeout * budgetFactor) + const Duration(seconds: 5);

/// Синхронизировано с serviceSweepBudgetFactor в core/service_check.go.
const serviceSweepBudgetFactor = 6;

const coreConnectionWaitDuration = Duration(seconds: 10);

/// Держать на уровне или ниже параллелизма тестов задержки ядра (`delayTestConcurrency`
/// в core/delay.go).
const maxConcurrentDelayTests = 32;
const maxConcurrentImports = 4;
const maxConcurrentIconLoads = 8;

const renderThrottleDuration = Duration(milliseconds: 300);
const defaultUpdateDuration = Duration(days: 1);
const MMDB = 'GEOIP.metadb';
const ASN = 'ASN.mmdb';
const GEOIP = 'GEOIP.dat';
const GEOSITE = 'GEOSITE.dat';

final double kHeaderHeight = getWindowHeaderHeight(
  isDesktop: system.isDesktop,
  isMacOS: system.isMacOS,
);
const profilesDirectoryName = 'profiles';
const providersDirectoryName = 'providers';
const proxiesProviderDirectoryName = 'proxies';
const rulesProviderDirectoryName = 'rules';

/// Ядро читает CA здесь, а map-локальные файлы только из [mitmResourcesDirectoryName].
const mitmDirectoryName = 'mitm';
const mitmModulesDirectoryName = 'modules';
const mitmResourcesDirectoryName = 'resources';

const localhost = '127.0.0.1';
const clashConfigKey = 'clash_config';
const configKey = 'config';
const systemDnsRecordKey = 'system_dns_record';
const bootRecordKey = 'boot_record';
const appliedConfigMd5Key = 'applied_config_md5';
const defaultSystemDnsFallback = '223.5.5.5';
const repository = 'Major-Woolfi/XClient';
const maxMobileWidth = 600;
const maxLaptopWidth = 840;
const defaultTestUrl = 'https://www.gstatic.com/generate_204';

const shareLinkSchemes = {
  'hysteria',
  'hysteria2',
  'hy2',
  'hysteria2+realm',
  'hy2+realm',
  'tuic',
  'trojan',
  'vless',
  'vmess',
  'ss',
  'ssr',
  'socks',
  'socks5',
  'socks5h',
  'anytls',
  'mierus',
};

/// Схемы нативных ссылок XRay (vmess://, vless://, trojan://, ss://, ssconf://).
const xrayLinkSchemes = {
  'vmess',
  'vless',
  'trojan',
  'shadowsocks',
  'ss',
  'ssconf',
};

const stringListEquality = ListEquality<String>();
const intListEquality = ListEquality<int>();
const ruleListEquality = ListEquality<Rule>();
const scriptListEquality = ListEquality<Script>();
const mitmModuleListEquality = ListEquality<MitmModule>();
const profileListEquality = ListEquality<Profile>();
const proxyGroupsEquality = ListEquality<ProxyGroup>();
const customProxiesEquality = ListEquality<CustomProxy>();
const clashProviderListEquality = ListEquality<ClashProvider>();
const iconSetListEquality = ListEquality<IconSet>();
const hotKeyActionListEquality = ListEquality<HotKeyAction>();
const stringAndStringMapEntryListEquality =
    ListEquality<MapEntry<String, String>>();
const keyboardModifierListEquality = SetEquality<KeyboardModifier>();

const proxiesListStoreKey = PageStorageKey<String>('proxies_list');
const toolsStoreKey = PageStorageKey<String>('tools');
const profilesStoreKey = PageStorageKey<String>('profiles');

const defaultPrimaryColor = 0xFF007AFF;

const maxLogsLength = 5000;
const maxRequestsLength = 2000;
const maxDnsQueriesLength = 3000;
const pausedMaxLogsLength = maxLogsLength * 2;
const pausedMaxRequestsLength = maxRequestsLength * 2;
const pausedMaxDnsQueriesLength = maxDnsQueriesLength * 2;

const trafficSampleLength = 30;

// iOS 27's системные цвета, но более глубокий синий ранних iOS, в порядке акцентных цветов macOS.
const defaultPrimaryColors = [
  defaultPrimaryColor,
  0xFFCB30E0,
  0xFFFF2D55,
  0xFFFF383C,
  0xFFFF8D28,
  0xFFFFCC00,
  0xFF34C759,
  0xFF8E8E93,
];

const scriptTemplate = '''
const main = (config) => {
  return config;
}''';

const backupDatabaseName = 'database.sqlite';
const configJsonName = 'config.json';
