// XRay link encoder/decoder (порт https://github.com/INCY-DEV/incy-link-encoder).
// Поддерживаемые схемы: vmess://, vless://, trojan://, ss://, ssconf://, v2ray://.
import 'dart:convert';

/// Тип прокси-ссылки XRay.
enum XrayLinkType { vmess, vless, trojan, shadowsocks, ssconf, unknown }

/// Распарсенная ссылка XRay.
class XrayLink {
  final XrayLinkType type;
  final String? tag;
  final String? address;
  final int? port;
  final String? uuid;
  final String? password;
  final String? method;
  final String? network;
  final String? security;
  final String? sni;
  final String? fingerprint;
  final String? alpn;
  final String? publicKey;
  final String? shortId;
  final String? spiderX;
  final String? flow;
  final bool? udp;
  final bool? grpc;
  final String? grpcServiceName;
  final String? wsPath;
  final String? wsHeaders;
  final String? altSni;
  final Map<String, dynamic>? extra;

  const XrayLink({
    required this.type,
    this.tag,
    this.address,
    this.port,
    this.uuid,
    this.password,
    this.method,
    this.network,
    this.security,
    this.sni,
    this.fingerprint,
    this.alpn,
    this.publicKey,
    this.shortId,
    this.spiderX,
    this.flow,
    this.udp,
    this.grpc,
    this.grpcServiceName,
    this.wsPath,
    this.wsHeaders,
    this.altSni,
    this.extra,
  });

  factory XrayLink.fromComponents({
    required XrayLinkType type,
    required String address,
    required int port,
    String? tag,
    String? uuid,
    String? password,
    String? method,
    String? network,
    String? security,
    String? sni,
    String? fingerprint,
    String? alpn,
    String? publicKey,
    String? shortId,
    String? spiderX,
    String? flow,
    bool? udp,
    bool? grpc,
    String? grpcServiceName,
    String? wsPath,
    Map<String, String>? wsHeaders,
    String? altSni,
  }) {
    return XrayLink(
      type: type,
      tag: tag,
      address: address,
      port: port,
      uuid: uuid,
      password: password,
      method: method,
      network: network,
      security: security,
      sni: sni,
      fingerprint: fingerprint,
      alpn: alpn,
      publicKey: publicKey,
      shortId: shortId,
      spiderX: spiderX,
      flow: flow,
      udp: udp,
      grpc: grpc,
      grpcServiceName: grpcServiceName,
      wsPath: wsPath,
      wsHeaders: wsHeaders != null ? jsonEncode(wsHeaders) : null,
      altSni: altSni,
    );
  }

  bool get isValid {
    if (address == null || address!.isEmpty) return false;
    if (port == null || port! <= 0 || port! > 65535) return false;
    switch (type) {
      case XrayLinkType.vmess:
      case XrayLinkType.vless:
      case XrayLinkType.trojan:
        return uuid != null || password != null;
      case XrayLinkType.shadowsocks:
        return method != null && password != null;
      default:
        return true;
    }
  }

  String toLink() {
    return switch (type) {
      XrayLinkType.vmess => _encodeVmess(),
      XrayLinkType.vless => _encodeVless(),
      XrayLinkType.trojan => _encodeTrojan(),
      XrayLinkType.shadowsocks => _encodeShadowsocks(),
      XrayLinkType.ssconf => _encodeSsconf(),
      XrayLinkType.unknown => '',
    };
  }

  String _encodeVmess() {
    final config = <String, dynamic>{
      'v': '2',
      'ps': tag ?? '',
      'add': address,
      'port': port,
      'id': uuid,
      'aid': 0,
      'net': network ?? 'tcp',
      'type': 'none',
      'host': sni,
      'path': wsPath ?? '',
      'tls': security == 'tls' || security == 'reality' ? 'tls' : '',
    };
    if (security == 'reality') {
      config['pbk'] = publicKey;
      config['sid'] = shortId;
      config['spx'] = spiderX;
    }
    final jsonStr = jsonEncode(config);
    final encoded = base64Url.encode(utf8.encode(jsonStr));
    return 'vmess://$encoded';
  }

  String _encodeVless() {
    final params = <String, String>{};
    if (security != null) params['security'] = security!;
    if (sni != null) params['sni'] = sni!;
    if (fingerprint != null) params['fp'] = fingerprint!;
    if (alpn != null) params['alpn'] = alpn!;
    if (publicKey != null) params['pbk'] = publicKey!;
    if (shortId != null) params['sid'] = shortId!;
    if (spiderX != null) params['spx'] = spiderX!;
    if (flow != null) params['flow'] = flow!;
    if (network != null) params['type'] = network!;
    if (wsPath != null) params['path'] = wsPath!;
    if (udp == true) params['udp'] = 'true';

    final query = params.isNotEmpty
        ? '?${params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&')}'
        : '';
    return 'vless://$uuid@$address:$port$query#${tag ?? ''}';
  }

  String _encodeTrojan() {
    final params = <String, String>{};
    if (security != null) params['security'] = security!;
    if (sni != null) params['sni'] = sni!;
    if (fingerprint != null) params['fp'] = fingerprint!;
    if (alpn != null) params['alpn'] = alpn!;
    if (network != null) params['type'] = network!;
    if (wsPath != null) params['path'] = wsPath!;
    if (udp == true) params['udp'] = 'true';

    final query = params.isNotEmpty
        ? '?${params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&')}'
        : '';
    return 'trojan://$password@$address:$port$query#${tag ?? ''}';
  }

  String _encodeShadowsocks() {
    final methodStr = method ?? 'aes-256-gcm';
    final cipher = '$methodStr:$password';
    final encoded = base64Url.encode(utf8.encode(cipher));
    final params = <String, String>{};
    if (security != null) params['security'] = security!;
    final query = params.isNotEmpty
        ? '?${params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&')}'
        : '';
    return 'ss://$encoded@$address:$port$query#${tag ?? ''}';
  }

  String _encodeSsconf() {
    return 'ssconf://${base64Url.encode(utf8.encode(toLink()))}';
  }

  @override
  String toString() => toLink();
}

XrayLink decodeXrayLink(String link) {
  final uri = Uri.tryParse(link);
  if (uri == null) {
    return const XrayLink(type: XrayLinkType.unknown);
  }

  final scheme = uri.scheme.toLowerCase();
  final type = switch (scheme) {
    'vmess' => XrayLinkType.vmess,
    'vless' => XrayLinkType.vless,
    'trojan' => XrayLinkType.trojan,
    'ss' => XrayLinkType.shadowsocks,
    'ssconf' => XrayLinkType.ssconf,
    'v2ray' => XrayLinkType.vmess,
    _ => XrayLinkType.unknown,
  };

  switch (type) {
    case XrayLinkType.vmess:
      return _decodeVmess(link, uri);
    case XrayLinkType.vless:
      return _decodeVless(uri);
    case XrayLinkType.trojan:
      return _decodeTrojan(uri);
    case XrayLinkType.shadowsocks:
      return _decodeShadowsocks(uri);
    case XrayLinkType.ssconf:
      return _decodeSsconf(link);
    case XrayLinkType.unknown:
      return const XrayLink(type: XrayLinkType.unknown);
  }
}

XrayLink _decodeVmess(String link, Uri uri) {
  final encoded = link.substring('vmess://'.length);
  String jsonStr;
  try {
    final padding = (4 - encoded.length % 4) % 4;
    final padded = encoded + '=' * padding;
    jsonStr = utf8.decode(base64Url.decode(padded));
  } catch (e) {
    return const XrayLink(type: XrayLinkType.unknown);
  }

  try {
    final Map<String, dynamic> config = jsonDecode(jsonStr);
    return XrayLink(
      type: XrayLinkType.vmess,
      tag: config['ps'] as String?,
      address: config['add'] as String?,
      port: (config['port'] as num?)?.toInt(),
      uuid: config['id'] as String?,
      method: config['scy'] as String?,
      network: config['net'] as String?,
      security: config['tls'] == 'tls' || config['tls'] == 'reality'
          ? 'tls'
          : 'none',
      sni: config['host'] as String?,
      fingerprint: config['fp'] as String?,
      alpn: config['alpn'] as String?,
      publicKey: config['pbk'] as String?,
      shortId: config['sid'] as String?,
      spiderX: config['spx'] as String?,
      wsPath: config['path'] as String?,
      extra: config,
    );
  } catch (e) {
    return const XrayLink(type: XrayLinkType.unknown);
  }
}

XrayLink _decodeVless(Uri uri) {
  return XrayLink(
    type: XrayLinkType.vless,
    tag: uri.fragment.isNotEmpty ? uri.fragment : null,
    address: uri.host,
    port: uri.port,
    uuid: uri.userInfo,
    security: uri.queryParameters['security'],
    sni: uri.queryParameters['sni'],
    fingerprint: uri.queryParameters['fp'],
    alpn: uri.queryParameters['alpn'],
    publicKey: uri.queryParameters['pbk'],
    shortId: uri.queryParameters['sid'],
    spiderX: uri.queryParameters['spx'],
    flow: uri.queryParameters['flow'],
    network: uri.queryParameters['type'],
    wsPath: uri.queryParameters['path'],
    udp: uri.queryParameters['udp'] == 'true',
    extra: uri.queryParameters,
  );
}

XrayLink _decodeTrojan(Uri uri) {
  return XrayLink(
    type: XrayLinkType.trojan,
    tag: uri.fragment.isNotEmpty ? uri.fragment : null,
    address: uri.host,
    port: uri.port,
    password: uri.userInfo.isNotEmpty ? uri.userInfo : null,
    security: uri.queryParameters['security'],
    sni: uri.queryParameters['sni'],
    fingerprint: uri.queryParameters['fp'],
    alpn: uri.queryParameters['alpn'],
    network: uri.queryParameters['type'],
    wsPath: uri.queryParameters['path'],
    udp: uri.queryParameters['udp'] == 'true',
    extra: uri.queryParameters,
  );
}

XrayLink _decodeShadowsocks(Uri uri) {
  try {
    final encoded = uri.userInfo;
    if (encoded.isEmpty) return const XrayLink(type: XrayLinkType.unknown);
    final padding = (4 - encoded.length % 4) % 4;
    final padded = encoded + '=' * padding;
    final decoded = utf8.decode(base64Url.decode(padded));
    final parts = decoded.split(':');
    if (parts.length < 2) return const XrayLink(type: XrayLinkType.unknown);

    return XrayLink(
      type: XrayLinkType.shadowsocks,
      tag: uri.fragment.isNotEmpty ? uri.fragment : null,
      address: uri.host,
      port: uri.port,
      method: parts[0],
      password: parts.sublist(1).join(':'),
      security: uri.queryParameters['security'],
      extra: uri.queryParameters,
    );
  } catch (e) {
    return const XrayLink(type: XrayLinkType.unknown);
  }
}

XrayLink _decodeSsconf(String link) {
  final encoded = link.substring('ssconf://'.length);
  try {
    final padding = (4 - encoded.length % 4) % 4;
    final padded = encoded + '=' * padding;
    final decoded = utf8.decode(base64Url.decode(padded));
    return decodeXrayLink(decoded);
  } catch (e) {
    return const XrayLink(type: XrayLinkType.unknown);
  }
}

Map<String, dynamic> xrayLinkToOutbound(XrayLink link) {
  final outbound = <String, dynamic>{
    'tag': link.tag ?? 'proxy',
    'protocol': switch (link.type) {
      XrayLinkType.vmess => 'vmess',
      XrayLinkType.vless => 'vless',
      XrayLinkType.trojan => 'trojan',
      XrayLinkType.shadowsocks => 'shadowsocks',
      _ => 'vmess',
    },
    'settings': <String, dynamic>{},
    'streamSettings': <String, dynamic>{},
  };

  switch (link.type) {
    case XrayLinkType.vmess:
      outbound['settings'] = {
        'vnext': [
          {
            'address': link.address,
            'port': link.port,
            'users': [
              {'id': link.uuid, 'alterId': 0, 'security': 'auto'},
            ],
          },
        ],
      };
      break;
    case XrayLinkType.vless:
      outbound['settings'] = {
        'vnext': [
          {
            'address': link.address,
            'port': link.port,
            'users': [
              {'id': link.uuid, 'encryption': 'none', 'flow': link.flow},
            ],
          },
        ],
      };
      break;
    case XrayLinkType.trojan:
      outbound['settings'] = {
        'servers': [
          {
            'address': link.address,
            'port': link.port,
            'password': link.password,
          },
        ],
      };
      break;
    case XrayLinkType.shadowsocks:
      outbound['settings'] = {
        'servers': [
          {
            'address': link.address,
            'port': link.port,
            'method': link.method,
            'password': link.password,
          },
        ],
      };
      break;
    default:
      break;
  }

  final stream = <String, dynamic>{};
  if (link.network != null) stream['network'] = link.network;
  if (link.security != null && link.security != 'none') {
    final tls = <String, dynamic>{'enabled': true, 'serverName': link.sni};
    if (link.fingerprint != null) tls['fingerprint'] = link.fingerprint;
    if (link.alpn != null) tls['alpn'] = [link.alpn];
    if (link.publicKey != null) {
      tls['reality'] = {
        'enabled': true,
        'publicKey': link.publicKey,
        'shortId': link.shortId,
        'spiderX': link.spiderX,
      };
    }
    stream['security'] = link.security;
    stream['tlsSettings'] = tls;
  }
  if (link.wsPath != null) {
    stream['wsSettings'] = {
      'path': link.wsPath,
      'headers': link.wsHeaders != null ? jsonDecode(link.wsHeaders!) : {},
    };
  }
  if (stream.isNotEmpty) {
    outbound['streamSettings'] = stream;
  }

  return outbound;
}

bool isXrayLink(String link) {
  final uri = Uri.tryParse(link);
  if (uri == null) return false;
  return switch (uri.scheme.toLowerCase()) {
    'vmess' || 'vless' || 'trojan' || 'ss' || 'ssconf' || 'v2ray' => true,
    _ => false,
  };
}
