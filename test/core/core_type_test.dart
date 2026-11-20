import 'package:xclient/core/core_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CoreType metadata', () {
    test('exposes labels, binary names and storage directories', () {
      expect(CoreType.clash.label, 'Clash.Meta');
      expect(CoreType.xray.label, 'Xray-core');
      expect(CoreType.clash.binaryName, 'XClientCore');
      expect(CoreType.xray.binaryName, 'XClientXray');
      expect(CoreType.clash.storageDir, 'cores/clash');
      expect(CoreType.xray.storageDir, 'cores/xray');
      expect(CoreType.clash.repo, 'MetaCubeX/mihomo');
      expect(CoreType.xray.repo, 'XTLS/Xray-core');
    });
  });

  group('CoreType.acceptsLink', () {
    test('clash recognises clash-family schemes', () {
      for (final link in [
        'clash://x',
        'clashmeta://x',
        'flclash://x',
        'xclient://x',
      ]) {
        expect(CoreType.clash.acceptsLink(link), isTrue, reason: link);
      }
      expect(CoreType.clash.acceptsLink('vmess://x'), isFalse);
    });

    test('xray recognises xray-family schemes', () {
      for (final link in [
        'vmess://x',
        'vless://x',
        'trojan://x',
        'ss://x',
        'ssconf://x',
        'v2ray://x',
      ]) {
        expect(CoreType.xray.acceptsLink(link), isTrue, reason: link);
      }
      expect(CoreType.xray.acceptsLink('clash://x'), isFalse);
    });
  });

  group('CoreType.acceptsConfig', () {
    test('rejects an empty config', () {
      expect(CoreType.clash.acceptsConfig('   '), isFalse);
      expect(CoreType.xray.acceptsConfig(''), isFalse);
    });

    test('scores clash keys against xray keys', () {
      const clash =
          'port: 7890\nmixed-port: 7891\nproxies:\nproxy-groups:\nrules:\n';
      expect(CoreType.clash.acceptsConfig(clash), isTrue);
      expect(CoreType.xray.acceptsConfig(clash), isFalse);

      const xray = 'inbounds:\noutbounds:\nroute:\n';
      expect(CoreType.xray.acceptsConfig(xray), isTrue);
      expect(CoreType.clash.acceptsConfig(xray), isFalse);
    });

    test('a tie goes to clash, never to xray', () {
      const tied = 'dns:\n';
      expect(CoreType.clash.acceptsConfig(tied), isTrue);
      expect(CoreType.xray.acceptsConfig(tied), isFalse);
    });

    test('only inspects the first twenty lines', () {
      final buffer = StringBuffer();
      for (var i = 0; i < 25; i++) {
        buffer.writeln('# filler $i');
      }
      buffer.writeln('inbounds:');
      expect(CoreType.xray.acceptsConfig(buffer.toString()), isFalse);
    });
  });

  group('CoreSpec', () {
    test('reads every field from JSON', () {
      final spec = CoreSpec.fromJson({
        'tag_name': 'v1.2.3',
        'download_url': 'https://example.com/core',
        'sha256': 'abc',
        'size': 42,
        'published_at': '2024-05-06T07:08:09Z',
        'prerelease': true,
      }, CoreType.xray);
      expect(spec.type, CoreType.xray);
      expect(spec.version, 'v1.2.3');
      expect(spec.downloadUrl, 'https://example.com/core');
      expect(spec.sha256, 'abc');
      expect(spec.size, 42);
      expect(spec.publishedAt, DateTime.utc(2024, 5, 6, 7, 8, 9));
      expect(spec.isPrerelease, isTrue);
      expect(spec.isInstalled, isFalse);
      expect(spec.versionWithV, 'vv1.2.3');
      expect(spec.displayLabel, 'Xray-core vv1.2.3 (pre-release)');

      final json = spec.toJson();
      expect(json['type'], 'xray');
      expect(json['published_at'], '2024-05-06T07:08:09.000Z');
      expect(json['prerelease'], isTrue);
      expect(json['installed'], isFalse);
    });

    test('falls back to defaults for missing JSON fields', () {
      final spec = CoreSpec.fromJson({}, CoreType.clash);
      expect(spec.version, isEmpty);
      expect(spec.downloadUrl, isEmpty);
      expect(spec.sha256, isEmpty);
      expect(spec.size, 0);
      expect(spec.isPrerelease, isFalse);
      expect(spec.publishedAt, isA<DateTime>());

      final versionOnly = CoreSpec.fromJson({
        'version': '9.9.9',
      }, CoreType.clash);
      expect(versionOnly.version, '9.9.9');

      final installed = CoreSpec(
        type: CoreType.clash,
        version: '1.0.0',
        downloadUrl: '',
        sha256: '',
        size: 0,
        publishedAt: DateTime.utc(2024),
        isInstalled: true,
      );
      expect(installed.displayLabel, 'Clash.Meta v1.0.0');
      expect(installed.toJson()['installed'], isTrue);
    });
  });

  group('CoreOperationResult', () {
    test('builds a success result with the spec', () {
      final spec = CoreSpec(
        type: CoreType.clash,
        version: '1.0.0',
        downloadUrl: '',
        sha256: '',
        size: 0,
        publishedAt: DateTime.utc(2024),
      );
      final result = CoreOperationResult.success(spec);
      expect(result.success, isTrue);
      expect(result.spec, same(spec));
      expect(result.error, isNull);
    });

    test('builds a failure result with an error message', () {
      final result = CoreOperationResult.failure('boom');
      expect(result.success, isFalse);
      expect(result.error, 'boom');
      expect(result.spec, isNull);
    });
  });
}
