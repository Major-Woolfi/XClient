import 'dart:convert';

import 'package:xclient/core/xray/xray_link_codec.dart';
import 'package:flutter_test/flutter_test.dart';

String _vmessLink(Map<String, dynamic> config) =>
    'vmess://${base64Url.encode(utf8.encode(jsonEncode(config)))}';

XrayLink _vmess({
  String? address = 'example.com',
  int? port = 443,
  String? uuid = 'uuid-1',
  String tag = 'tag',
  String? network,
  String? security,
  String? sni,
  String? fingerprint,
  String? alpn,
  String? publicKey,
  String? shortId,
  String? spiderX,
  String? wsPath,
}) {
  return XrayLink(
    type: XrayLinkType.vmess,
    tag: tag,
    address: address,
    port: port,
    uuid: uuid,
    network: network,
    security: security,
    sni: sni,
    fingerprint: fingerprint,
    alpn: alpn,
    publicKey: publicKey,
    shortId: shortId,
    spiderX: spiderX,
    wsPath: wsPath,
  );
}

void main() {
  group('XrayLink.isValid', () {
    test('accepts vmess, vless and trojan with an id or password', () {
      expect(_vmess().isValid, isTrue);
      expect(
        const XrayLink(
          type: XrayLinkType.vless,
          address: 'a',
          port: 1,
          password: 'p',
        ).isValid,
        isTrue,
      );
      expect(
        const XrayLink(
          type: XrayLinkType.trojan,
          address: 'a',
          port: 1,
          uuid: 'u',
        ).isValid,
        isTrue,
      );
    });

    test('rejects a credentials-less vmess', () {
      expect(_vmess(uuid: null).isValid, isFalse);
    });

    test('requires method and password for shadowsocks', () {
      expect(
        const XrayLink(
          type: XrayLinkType.shadowsocks,
          address: 'a',
          port: 1,
          method: 'aes-256-gcm',
          password: 'p',
        ).isValid,
        isTrue,
      );
      expect(
        const XrayLink(
          type: XrayLinkType.shadowsocks,
          address: 'a',
          port: 1,
          method: 'aes-256-gcm',
        ).isValid,
        isFalse,
      );
      expect(
        const XrayLink(
          type: XrayLinkType.shadowsocks,
          address: 'a',
          port: 1,
          password: 'p',
        ).isValid,
        isFalse,
      );
    });

    test('accepts ssconf and unknown once address and port are set', () {
      expect(
        const XrayLink(
          type: XrayLinkType.ssconf,
          address: 'a',
          port: 1,
        ).isValid,
        isTrue,
      );
      expect(
        const XrayLink(
          type: XrayLinkType.unknown,
          address: 'a',
          port: 1,
        ).isValid,
        isTrue,
      );
    });

    test('rejects a missing or empty address and an out-of-range port', () {
      expect(_vmess(address: null).isValid, isFalse);
      expect(_vmess(address: '').isValid, isFalse);
      expect(_vmess(port: null).isValid, isFalse);
      expect(_vmess(port: 0).isValid, isFalse);
      expect(_vmess(port: 65536).isValid, isFalse);
    });
  });

  group('XrayLink.toLink', () {
    test('encodes vmess as base64url JSON', () {
      final link = _vmess(network: 'ws', wsPath: '/path');
      final encoded = link.toLink();
      expect(encoded, startsWith('vmess://'));
      final json =
          jsonDecode(
                utf8.decode(
                  base64Url.decode(encoded.substring('vmess://'.length)),
                ),
              )
              as Map<String, dynamic>;
      expect(json['ps'], 'tag');
      expect(json['add'], 'example.com');
      expect(json['port'], 443);
      expect(json['id'], 'uuid-1');
      expect(json['aid'], 0);
      expect(json['net'], 'ws');
      expect(json['path'], '/path');
      expect(json['tls'], '');
      expect(link.toString(), encoded);
    });

    test('adds tls settings and reality keys to a vmess link', () {
      final tlsLink = _vmess(security: 'tls');
      expect(
        jsonDecode(
          utf8.decode(
            base64Url.decode(tlsLink.toLink().substring('vmess://'.length)),
          ),
        )['tls'],
        'tls',
      );

      final reality = _vmess(
        security: 'reality',
        publicKey: 'pbk',
        shortId: 'sid',
        spiderX: 'spx',
      );
      final json =
          jsonDecode(
                utf8.decode(
                  base64Url.decode(
                    reality.toLink().substring('vmess://'.length),
                  ),
                ),
              )
              as Map<String, dynamic>;
      expect(json['tls'], 'tls');
      expect(json['pbk'], 'pbk');
      expect(json['sid'], 'sid');
      expect(json['spx'], 'spx');
    });

    test('encodes vless with every optional parameter', () {
      final link = XrayLink.fromComponents(
        type: XrayLinkType.vless,
        address: 'host',
        port: 80,
        tag: 'name',
        uuid: 'uuid',
        security: 'reality',
        sni: 'sni',
        fingerprint: 'fp',
        alpn: 'h2',
        publicKey: 'pbk',
        shortId: 'sid',
        spiderX: '/spx',
        flow: 'xtls-rprx-vision',
        network: 'ws',
        wsPath: '/ws',
        udp: true,
      );
      final encoded = link.toLink();
      expect(encoded, startsWith('vless://uuid@host:80?'));
      expect(encoded, endsWith('#name'));
      final uri = Uri.parse(encoded);
      expect(uri.queryParameters['security'], 'reality');
      expect(uri.queryParameters['sni'], 'sni');
      expect(uri.queryParameters['fp'], 'fp');
      expect(uri.queryParameters['alpn'], 'h2');
      expect(uri.queryParameters['pbk'], 'pbk');
      expect(uri.queryParameters['sid'], 'sid');
      expect(uri.queryParameters['spx'], '/spx');
      expect(uri.queryParameters['flow'], 'xtls-rprx-vision');
      expect(uri.queryParameters['type'], 'ws');
      expect(uri.queryParameters['path'], '/ws');
      expect(uri.queryParameters['udp'], 'true');
      expect(link.wsHeaders, isNull);
    });

    test('encodes a minimal vless link without a query', () {
      const link = XrayLink(
        type: XrayLinkType.vless,
        address: 'host',
        port: 80,
        uuid: 'uuid',
      );
      expect(link.toLink(), 'vless://uuid@host:80#');
    });

    test('encodes trojan with and without optional parameters', () {
      const full = XrayLink(
        type: XrayLinkType.trojan,
        address: 'host',
        port: 443,
        password: 'secret',
        tag: 'name',
        security: 'tls',
        sni: 'sni',
        fingerprint: 'fp',
        alpn: 'h2',
        network: 'grpc',
        wsPath: '/p',
        udp: true,
      );
      final uri = Uri.parse(full.toLink());
      expect(uri.userInfo, 'secret');
      expect(uri.queryParameters['security'], 'tls');
      expect(uri.queryParameters['sni'], 'sni');
      expect(uri.queryParameters['fp'], 'fp');
      expect(uri.queryParameters['alpn'], 'h2');
      expect(uri.queryParameters['type'], 'grpc');
      expect(uri.queryParameters['path'], '/p');
      expect(uri.queryParameters['udp'], 'true');

      const minimal = XrayLink(
        type: XrayLinkType.trojan,
        address: 'host',
        port: 443,
        password: 'secret',
      );
      expect(minimal.toLink(), 'trojan://secret@host:443#');
    });

    test('encodes shadowsocks with a default method and optional security', () {
      const link = XrayLink(
        type: XrayLinkType.shadowsocks,
        address: 'host',
        port: 8388,
        password: 'pass',
      );
      final encoded = link.toLink();
      final decoded = utf8.decode(
        base64Url.decode(encoded.split('@').first.substring('ss://'.length)),
      );
      expect(decoded, 'aes-256-gcm:pass');

      final secured = Uri.parse(
        const XrayLink(
          type: XrayLinkType.shadowsocks,
          address: 'host',
          port: 8388,
          method: 'chacha20-ietf-poly1305',
          password: 'pass',
          security: 'tls',
        ).toLink(),
      );
      expect(secured.queryParameters['security'], 'tls');
    });

    test('encodes an empty unknown link', () {
      expect(const XrayLink(type: XrayLinkType.unknown).toLink(), isEmpty);
    });
  });

  group('decodeXrayLink', () {
    test('returns unknown for a link that is not a URI', () {
      expect(decodeXrayLink('not a uri').type, XrayLinkType.unknown);
      expect(decodeXrayLink('http://example.com').type, XrayLinkType.unknown);
    });

    test('decodes a vmess link with all fields', () {
      final link = decodeXrayLink(
        _vmessLink({
          'v': '2',
          'ps': 'name',
          'add': 'host',
          'port': 443,
          'id': 'uuid',
          'scy': 'auto',
          'net': 'ws',
          'tls': 'tls',
          'host': 'sni',
          'fp': 'fp',
          'alpn': 'h2',
          'pbk': 'pbk',
          'sid': 'sid',
          'spx': '/spx',
          'path': '/path',
        }),
      );
      expect(link.type, XrayLinkType.vmess);
      expect(link.tag, 'name');
      expect(link.address, 'host');
      expect(link.port, 443);
      expect(link.uuid, 'uuid');
      expect(link.method, 'auto');
      expect(link.network, 'ws');
      expect(link.security, 'tls');
      expect(link.sni, 'sni');
      expect(link.fingerprint, 'fp');
      expect(link.alpn, 'h2');
      expect(link.publicKey, 'pbk');
      expect(link.shortId, 'sid');
      expect(link.spiderX, '/spx');
      expect(link.wsPath, '/path');
      expect(link.extra, isA<Map<String, dynamic>>());
    });

    test('decodes a reality vmess link and a non-tls one', () {
      final reality = decodeXrayLink(
        _vmessLink({'add': 'host', 'port': 1, 'tls': 'reality'}),
      );
      expect(reality.security, 'tls');

      final plain = decodeXrayLink(
        _vmessLink({'add': 'host', 'port': 1, 'tls': ''}),
      );
      expect(plain.security, 'none');
    });

    test('returns unknown for malformed vmess links', () {
      expect(decodeXrayLink('vmess://%%%').type, XrayLinkType.unknown);
      final badJson = 'vmess://${base64Url.encode(utf8.encode('not json'))}';
      expect(decodeXrayLink(badJson).type, XrayLinkType.unknown);
    });

    test('decodes vless and v2ray links', () {
      final vless = decodeXrayLink(
        'vless://uuid@host:443?security=tls&sni=s&fp=f&alpn=h2&pbk=p&sid=s&spx=/x&flow=fl&type=ws&path=/p&udp=true#tag',
      );
      expect(vless.type, XrayLinkType.vless);
      expect(vless.uuid, 'uuid');
      expect(vless.address, 'host');
      expect(vless.port, 443);
      expect(vless.tag, 'tag');
      expect(vless.security, 'tls');
      expect(vless.sni, 's');
      expect(vless.fingerprint, 'f');
      expect(vless.alpn, 'h2');
      expect(vless.publicKey, 'p');
      expect(vless.shortId, 's');
      expect(vless.spiderX, '/x');
      expect(vless.flow, 'fl');
      expect(vless.network, 'ws');
      expect(vless.wsPath, '/p');
      expect(vless.udp, isTrue);
      expect(vless.extra, isA<Map<String, String>>());

      final noTag = decodeXrayLink('vless://uuid@host:1');
      expect(noTag.tag, isNull);
      expect(decodeXrayLink('v2ray://uuid@host:1').type, XrayLinkType.unknown);
    });

    test('decodes trojan links', () {
      final link = decodeXrayLink(
        'trojan://pass@host:443?security=tls&sni=s&fp=f&alpn=h2&type=grpc&path=/p&udp=true#tag',
      );
      expect(link.type, XrayLinkType.trojan);
      expect(link.password, 'pass');
      expect(link.tag, 'tag');
      expect(link.security, 'tls');
      expect(link.sni, 's');
      expect(link.network, 'grpc');
      expect(link.udp, isTrue);
      expect(decodeXrayLink('trojan://host:1').password, isNull);
      expect(decodeXrayLink('trojan://host:1').tag, isNull);
    });

    test('decodes shadowsocks links including malformed ones', () {
      final creds = base64Url.encode(
        utf8.encode('aes-256-gcm:pass:with:colons'),
      );
      final link = decodeXrayLink('ss://$creds@host:8388?security=tls#name');
      expect(link.type, XrayLinkType.shadowsocks);
      expect(link.method, 'aes-256-gcm');
      expect(link.password, 'pass:with:colons');
      expect(link.tag, 'name');
      expect(link.security, 'tls');
      expect(link.extra, isA<Map<String, String>>());

      expect(decodeXrayLink('ss://host:1').type, XrayLinkType.unknown);
      expect(decodeXrayLink('ss://%%%@host:1').type, XrayLinkType.unknown);
      final noColon = base64Url.encode(utf8.encode('nocolon'));
      expect(decodeXrayLink('ss://$noColon@host:1').type, XrayLinkType.unknown);
    });

    test('decodes ssconf links and rejects malformed ones', () {
      const inner = 'vless://uuid@host:443#tag';
      final encoded = base64Url.encode(utf8.encode(inner));
      final decodedLink = decodeXrayLink('ssconf://$encoded');
      expect(decodedLink.type, XrayLinkType.vless);
      expect(decodedLink.tag, 'tag');
      expect(decodeXrayLink('ssconf://%%%').type, XrayLinkType.unknown);
    });
  });

  group('xrayLinkToOutbound', () {
    test('builds settings for each protocol', () {
      final vmess = xrayLinkToOutbound(_vmess());
      expect(vmess['protocol'], 'vmess');
      expect(
        (vmess['settings']
            as Map<String, dynamic>)['vnext'][0]['users'][0]['id'],
        'uuid-1',
      );

      final vless = xrayLinkToOutbound(
        const XrayLink(
          type: XrayLinkType.vless,
          address: 'h',
          port: 1,
          uuid: 'u',
          flow: 'flow',
        ),
      );
      expect(vless['protocol'], 'vless');
      expect(
        (vless['settings']
            as Map<String, dynamic>)['vnext'][0]['users'][0]['flow'],
        'flow',
      );

      final trojan = xrayLinkToOutbound(
        const XrayLink(
          type: XrayLinkType.trojan,
          address: 'h',
          port: 1,
          password: 'p',
        ),
      );
      expect(trojan['protocol'], 'trojan');
      expect(
        (trojan['settings'] as Map<String, dynamic>)['servers'][0]['password'],
        'p',
      );

      final ss = xrayLinkToOutbound(
        const XrayLink(
          type: XrayLinkType.shadowsocks,
          address: 'h',
          port: 1,
          method: 'aes-128-gcm',
          password: 'p',
        ),
      );
      expect(ss['protocol'], 'shadowsocks');
      expect(
        (ss['settings'] as Map<String, dynamic>)['servers'][0]['method'],
        'aes-128-gcm',
      );
    });

    test('builds stream settings for tls, reality and websocket', () {
      final outbound = xrayLinkToOutbound(
        XrayLink(
          type: XrayLinkType.vmess,
          address: 'h',
          port: 1,
          uuid: 'u',
          network: 'ws',
          security: 'tls',
          sni: 'sni',
          fingerprint: 'fp',
          alpn: 'h2',
          publicKey: 'pbk',
          shortId: 'sid',
          spiderX: '/x',
          wsPath: '/path',
          wsHeaders: jsonEncode({'Host': 'example.com'}),
        ),
      );
      final stream = outbound['streamSettings'] as Map<String, dynamic>;
      expect(stream['network'], 'ws');
      expect(stream['security'], 'tls');
      final tls = stream['tlsSettings'] as Map<String, dynamic>;
      expect(tls['enabled'], isTrue);
      expect(tls['serverName'], 'sni');
      expect(tls['fingerprint'], 'fp');
      expect(tls['alpn'], ['h2']);
      expect((tls['reality'] as Map<String, dynamic>)['publicKey'], 'pbk');
      final ws = stream['wsSettings'] as Map<String, dynamic>;
      expect(ws['path'], '/path');
      expect(ws['headers'], {'Host': 'example.com'});
    });

    test('falls back to vmess settings for other link types', () {
      final outbound = xrayLinkToOutbound(
        const XrayLink(type: XrayLinkType.ssconf),
      );
      expect(outbound['protocol'], 'vmess');
      expect(outbound['streamSettings'], isEmpty);
    });
  });

  group('isXrayLink', () {
    test('recognises xray schemes', () {
      for (final scheme in [
        'vmess',
        'vless',
        'trojan',
        'ss',
        'ssconf',
        'v2ray',
      ]) {
        expect(isXrayLink('$scheme://x'), isTrue);
      }
    });

    test('rejects other schemes and malformed links', () {
      expect(isXrayLink('http://example.com'), isFalse);
      expect(isXrayLink('not a uri'), isFalse);
    });
  });
}
