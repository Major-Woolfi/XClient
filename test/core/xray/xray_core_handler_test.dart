import 'dart:convert';
import 'dart:io';

import 'package:xclient/core/desktop/model.dart';
import 'package:xclient/core/method.dart';
import 'package:xclient/core/xray/xray_core_handler.dart';
import 'package:xclient/enum/enum.dart';
import 'package:xclient/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../helpers/app_paths.dart';
import '../../helpers/preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory home;
  late XRayCoreHandler handler;

  UpdateParams updateParams() => const UpdateParams(
    tun: Tun(),
    mixedPort: 7890,
    allowLan: true,
    findProcessMode: FindProcessMode.off,
    mode: Mode.rule,
    logLevel: LogLevel.info,
    ipv6: false,
    tcpConcurrent: false,
    externalController: ExternalControllerStatus.close,
    unifiedDelay: false,
    options: CoreOptions(testUrl: 'http://x.com'),
  );

  setUp(() async {
    home = Directory.systemTemp.createTempSync('xray_core_handler_test');
    await useAppPaths(home);
    await mockPreferences();
    XRayCoreHandler.resetInstance();
    handler = XRayCoreHandler();
  });

  tearDown(() {
    XRayCoreHandler.resetInstance();
    home.deleteSync(recursive: true);
  });

  Future<void> connect() =>
      handler.init(const InitParams(homeDir: 'x', version: 0));

  group('lifecycle', () {
    test('start reports a missing binary instead of spawning a process', () {
      expect(handler.start(), throwsA(isA<StateError>()));
    });

    test('restart stops first, then fails on the missing binary', () {
      expect(handler.restart(), throwsA(isA<StateError>()));
    });

    test('stop and close coalesce while disconnected', () async {
      final stopped = await handler.stop();
      expect(stopped.outcome, CoreLifecycleOutcome.coalesced);
      expect((await handler.close()).outcome, CoreLifecycleOutcome.coalesced);
    });

    test('stop applies and clears the connected state', () async {
      await connect();
      expect(await handler.isInit, isTrue);
      final stopped = await handler.stop();
      expect(stopped.outcome, CoreLifecycleOutcome.applied);
      expect(await handler.isInit, isFalse);
    });

    test('crash clears the connected state with no process', () async {
      await connect();
      await handler.crash();
      expect(await handler.isInit, isFalse);
    });
  });

  group('config files', () {
    late String validPath;
    late String invalidPath;

    setUp(() {
      validPath = p.join(home.path, 'valid.json');
      invalidPath = p.join(home.path, 'invalid.json');
      File(validPath).writeAsStringSync('{"log":{"loglevel":"info"}}');
      File(invalidPath).writeAsStringSync('not json');
    });

    test(
      'validateConfig distinguishes valid, invalid and missing files',
      () async {
        expect(await handler.validateConfig(validPath), isNull);
        expect(
          await handler.validateConfig(invalidPath),
          startsWith('Invalid JSON:'),
        );
        expect(
          await handler.validateConfig(p.join(home.path, 'missing.json')),
          'Config file not found',
        );
      },
    );

    test(
      'readConfig decodes a file and returns empty for a missing one',
      () async {
        expect(await handler.readConfig(validPath), {
          'log': {'loglevel': 'info'},
        });
        expect(
          await handler.readConfig(p.join(home.path, 'missing.json')),
          isEmpty,
        );
      },
    );

    test('setupConfig writes only recognised top-level keys', () async {
      await handler.setupConfig(
        const SetupParams(
          selectedMap: {},
          options: CoreOptions(testUrl: 'http://x.com'),
        ),
      );
      final config =
          jsonDecode(
                await File(
                  p.join(home.path, 'xray', 'config.json'),
                ).readAsString(),
              )
              as Map<String, dynamic>;
      expect(config, isEmpty);
    });

    test('updateConfig writes the config then fails restarting', () async {
      await expectLater(
        handler.updateConfig(updateParams()),
        throwsA(isA<StateError>()),
      );
      expect(
        File(p.join(home.path, 'xray', 'config.json')).existsSync(),
        isTrue,
      );
    });
  });

  group('proxies and profiles', () {
    test('getProxies is empty before a config is written', () async {
      final proxies = await handler.getProxies();
      expect(proxies.proxies, isEmpty);
      expect(proxies.all, isEmpty);
    });

    test('getProxies parses outbounds from the written config', () async {
      await connect();
      await handler.invokeMethod(
        method: CoreMethod.configSetup,
        arguments: {
          'outbounds': [
            {
              'tag': 'proxy',
              'protocol': 'vless',
              'settings': {'id': 'uuid'},
            },
            {'protocol': 'freedom', 'tag': 'direct'},
            'not a map',
            {'protocol': 'blackhole'},
          ],
        },
      );

      final proxies = await handler.getProxies();
      expect(proxies.all, ['proxy', 'direct']);
      expect(proxies.proxies['proxy']['type'], 'vless');
      expect(proxies.proxies['direct']['name'], 'direct');

      final definition = await handler.getProxyDefinition('proxy');
      expect(definition?['protocol'], 'vless');
      expect(await handler.getProxyDefinition('missing'), isNull);
    });

    test(
      'getProxies and getProxyDefinition survive a corrupt config',
      () async {
        await connect();
        await handler.invokeMethod(
          method: CoreMethod.configSetup,
          arguments: {'outbounds': []},
        );
        final configPath = p.join(home.path, 'xray', 'config.json');
        await File(configPath).writeAsString('not json');

        expect((await handler.getProxies()).all, isEmpty);
        expect(await handler.getProxyDefinition('proxy'), isNull);
      },
    );

    test('profile placeholders have the documented shape', () async {
      expect((await handler.getProfileBase('x')).config, isEmpty);
      expect((await handler.getProfileOutbounds('x')), isEmpty);
      expect(
        await handler.buildProfile(const SetupBase(path: '', overlay: '')),
        '{}',
      );
      await handler.clearEffect(1);
    });
  });

  group('fixed-value interface methods', () {
    test('memory stats come from the local stub', () async {
      final stats = await handler.getMemoryStats();
      expect(stats.rss, 0);
      expect(stats.heapInuse, 0);
      expect(stats.heapIdle, 0);
      expect(stats.stackInuse, 0);
      expect(stats.runtimeOther, 0);
    });

    test('change proxy is answered as unsupported', () async {
      final result = await handler.changeProxy(
        const ChangeProxyParams(groupName: 'g', proxyName: 'p'),
      );
      expect(result.changed, isFalse);
      expect(result.message, contains('config edit and restart'));
    });

    test(
      'delay, filters, providers and rule sets return empty stubs',
      () async {
        expect(
          await handler.testDelay(
            const TestDelayParams(proxyName: 'p', testUrl: 'u', timeout: 0),
          ),
          const Delay(name: '', url: '', value: -1),
        );
        expect(await handler.validateProxies([]), isEmpty);
        expect(await handler.convertProxies('x'), isEmpty);
        expect(await handler.validateFilters([]), isEmpty);
        expect(await handler.getExternalProviders(), isEmpty);
        expect(await handler.getExternalProvider('p'), isNull);
        await handler.updateExternalProvider('p');
        await handler.sideLoadExternalProvider(providerName: 'p', data: 'd');
        expect(await handler.dumpRuleSet('x'), isEmpty);
        final compiled = await handler.compileRuleSet('name');
        expect(compiled.behavior, RuleProviderBehavior.domain);
        expect(compiled.format, RuleProviderFormat.yaml);
        await handler.updateGeoData('MMDB');
      },
    );

    test('traffic and connection stubs are empty', () async {
      expect(await handler.getTraffic(false), const Traffic(up: 0, down: 0));
      expect(
        await handler.getTotalTraffic(true),
        const Traffic(up: 0, down: 0),
      );
      await handler.resetTraffic();
      expect(await handler.getConnections(), isEmpty);
      expect(await handler.getConnectionCount(), 0);
      await handler.closeConnection('1');
      await handler.closeConnections();
      await handler.resetConnections();
      await handler.clearDnsCache();
      await handler.reportNetworkChange();
      await handler.startLog();
      await handler.stopLog();
      await handler.startListener();
      await handler.stopListener();
      await handler.forceGc();
    });

    test('route and probe stubs are empty', () async {
      expect(
        await handler.watchRoute(true),
        const RouteSnapshot(coreEpoch: 0, routeVersion: 0),
      );
      expect(
        await handler.checkRoutes(const CheckRoutesParams()),
        const RouteCheck(),
      );
      final ip = await handler.outboundIp(const OutboundIpParams(timeout: 1));
      expect(ip.url, isEmpty);
      expect(ip.nodeHits, isEmpty);
      expect(
        await handler.serviceCheck(const ServiceCheckParams(timeout: 1)),
        isEmpty,
      );
    });

    test('mitm methods are unsupported or empty', () async {
      expect(await handler.getMitmCertificate(), isNull);
      expect(
        handler.generateMitmCertificate(),
        throwsA(isA<UnimplementedError>()),
      );
      expect(await handler.validateMitm(const MitmRules()), isEmpty);
      expect(
        handler.issueMitmCertificate('host'),
        throwsA(isA<UnimplementedError>()),
      );
      expect((await handler.getMitmExchanges('1')).exchanges, isEmpty);
      expect(await handler.getMitmExchange(1), isNull);
      expect(await handler.getMitmBody(1, response: true), isNull);
      expect(
        handler.runMitmScript('script'),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('age configs are not supported', () {
      expect(
        handler.decryptConfig('x', 'key'),
        throwsA(isA<UnimplementedError>()),
      );
    });
  });

  group('invokeMethod', () {
    test('rejects calls while disconnected', () {
      expect(
        handler.invokeMethod(method: CoreMethod.coreGc),
        throwsA(
          isA<CoreMethodException>().having(
            (e) => e.code,
            'code',
            'core_unavailable',
          ),
        ),
      );
    });

    test('dispatches init, memory and gc methods', () async {
      await connect();
      expect(await handler.invokeMethod(method: CoreMethod.coreInit), isNull);
      expect(
        await handler.invokeMethod(method: CoreMethod.coreInitialized),
        isTrue,
      );
      expect(await handler.invokeMethod(method: CoreMethod.coreGc), isNull);
      expect(
        await handler.invokeMethod(method: CoreMethod.coreMemory),
        isA<Map<String, dynamic>>(),
      );
    });

    test('dispatches config validate and read with arguments', () async {
      await connect();
      final validPath = p.join(home.path, 'valid.json');
      File(validPath).writeAsStringSync('{"a":1}');
      expect(
        await handler.invokeMethod(
          method: CoreMethod.configValidate,
          arguments: {'path': validPath},
        ),
        isNull,
      );
      expect(
        await handler.invokeMethod(
          method: CoreMethod.configValidate,
          arguments: <String, dynamic>{},
        ),
        'Config file not found',
      );
      expect(
        await handler.invokeMethod(
          method: CoreMethod.configRead,
          arguments: {'path': validPath},
        ),
        {'a': 1},
      );
      expect(
        await handler.invokeMethod(
          method: CoreMethod.configRead,
          arguments: const <String, dynamic>{},
        ),
        isEmpty,
      );
    });

    test('dispatches config setup with null and with a config', () async {
      await connect();
      expect(
        await handler.invokeMethod(method: CoreMethod.configSetup),
        isNull,
      );
      expect(
        await handler.invokeMethod(
          method: CoreMethod.configSetup,
          arguments: {'outbounds': []},
        ),
        isNull,
      );
      expect(
        await handler.invokeMethod(method: CoreMethod.configUpdate),
        isNull,
      );
    });

    test('dispatches the profile and proxy stubs', () async {
      await connect();
      expect(
        await handler.invokeMethod(method: CoreMethod.profileBase),
        isA<Map<String, dynamic>>(),
      );
      expect(
        await handler.invokeMethod(method: CoreMethod.profileOutbounds),
        isEmpty,
      );
      expect(await handler.invokeMethod(method: CoreMethod.profileBuild), '{}');
      expect(
        await handler.invokeMethod(method: CoreMethod.proxyList),
        isA<Map<String, dynamic>>(),
      );
      expect(await handler.invokeMethod(method: CoreMethod.proxySelect), {
        'changed': false,
        'selected': '',
      });
      expect(await handler.invokeMethod(method: CoreMethod.proxyTestDelay), {
        'delay': -1,
        'alive': false,
      });
    });

    test('dispatches share-link encode and decode', () async {
      await connect();
      expect(
        await handler.invokeMethod(method: CoreMethod.shareLinkEncode),
        isEmpty,
      );
      expect(
        await handler.invokeMethod(method: CoreMethod.shareLinkDecode),
        isEmpty,
      );

      final encoded = await handler.invokeMethod(
        method: CoreMethod.shareLinkEncode,
        arguments: [
          {'type': 'vless', 'address': 'host', 'port': 443, 'uuid': 'uuid'},
        ],
      );
      expect(encoded, isA<List<String>>());
      expect((encoded as List<String>).first, startsWith('vless://'));

      final decoded = await handler.invokeMethod(
        method: CoreMethod.shareLinkDecode,
        arguments: ['vless://uuid@host:443'],
      );
      expect(decoded, isA<List<List<Map<String, dynamic>>>>());
      expect((decoded as List).first.first['protocol'], 'vless');
    });

    test('dispatches traffic, connection and listener stubs', () async {
      await connect();
      expect(
        await handler.invokeMethod(method: CoreMethod.trafficCurrent),
        isA<Map<String, dynamic>>(),
      );
      expect(
        await handler.invokeMethod(method: CoreMethod.trafficTotal),
        isA<Map<String, dynamic>>(),
      );
      expect(
        await handler.invokeMethod(method: CoreMethod.connectionList),
        isEmpty,
      );
      expect(
        await handler.invokeMethod(method: CoreMethod.connectionClose),
        isNull,
      );
      expect(
        await handler.invokeMethod(method: CoreMethod.connectionCloseAll),
        isNull,
      );
      expect(
        await handler.invokeMethod(method: CoreMethod.listenerStart),
        isNull,
      );
      expect(
        await handler.invokeMethod(method: CoreMethod.listenerStop),
        isNull,
      );
    });

    test('throws for an unsupported method', () async {
      await connect();
      expect(
        handler.invokeMethod(method: CoreMethod.coreCrash),
        throwsA(isA<UnimplementedError>()),
      );
    });
  });

  group('share link delegation', () {
    test(
      'encodeShareLinks and decodeShareLinks delegate to the controller',
      () async {
        final encoded = await handler.encodeShareLinks([
          {'type': 'trojan', 'address': 'host', 'port': 443, 'password': 'p'},
        ]);
        expect(encoded.first, startsWith('trojan://'));

        final decoded = await handler.decodeShareLinks(['trojan://p@host:443']);
        expect(decoded.first.first['protocol'], 'trojan');
      },
    );
  });
}
