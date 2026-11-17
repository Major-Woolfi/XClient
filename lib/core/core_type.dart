/// Тип ядра прокси-клиента.
enum CoreType {
  /// Clash.Meta (mihomo) - текущее ядро по умолчанию.
  clash,

  /// Xray-core (XTLS) - новое ядро.
  xray,
}

extension CoreTypeExtension on CoreType {
  /// Человекочитаемое название ядра.
  String get label {
    switch (this) {
      case CoreType.clash:
        return 'Clash.Meta';
      case CoreType.xray:
        return 'Xray-core';
    }
  }

  /// Имя исполняемого файла ядра для текущей платформы.
  String get binaryName {
    switch (this) {
      case CoreType.clash:
        return 'XClientCore';
      case CoreType.xray:
        return 'XClientXray';
    }
  }

  /// Префикс для именования директорий ядра в хранилище.
  String get storageDir {
    switch (this) {
      case CoreType.clash:
        return 'cores/clash';
      case CoreType.xray:
        return 'cores/xray';
    }
  }

  /// URL репозитория для получения релизов ядра.
  String get repo {
    switch (this) {
      case CoreType.clash:
        return 'MetaCubeX/mihomo';
      case CoreType.xray:
        return 'XTLS/Xray-core';
    }
  }

  /// Может ли ядро работать с данной ссылкой.
  bool acceptsLink(String link) {
    switch (this) {
      case CoreType.clash:
        return link.startsWith('clash://') ||
            link.startsWith('clashmeta://') ||
            link.startsWith('flclash://') ||
            link.startsWith('xclient://');
      case CoreType.xray:
        return link.startsWith('vmess://') ||
            link.startsWith('vless://') ||
            link.startsWith('trojan://') ||
            link.startsWith('ss://') ||
            link.startsWith('ssconf://') ||
            link.startsWith('v2ray://');
    }
  }

  /// Может ли ядро работать с данным конфигом (по содержимому YAML/JSON).
  bool acceptsConfig(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return false;

    final clashKeys = [
      'proxies:',
      'proxy-groups:',
      'rules:',
      'port:',
      'mixed-port:',
      'dns:',
    ];
    final xrayKeys = ['inbounds:', 'outbounds:', 'dns:', 'route:'];

    final lines = trimmed.split('\n').take(20).join('\n').toLowerCase();

    int clashScore = 0;
    int xrayScore = 0;

    for (final key in clashKeys) {
      if (lines.contains(key)) clashScore++;
    }
    for (final key in xrayKeys) {
      if (lines.contains(key)) xrayScore++;
    }

    if (this == CoreType.clash) {
      return clashScore >= xrayScore && clashScore > 0;
    } else {
      return xrayScore > clashScore && xrayScore > 0;
    }
  }
}

/// Спецификация версии ядра.
class CoreSpec {
  final CoreType type;
  final String version;
  final String downloadUrl;
  final String sha256;
  final int size;
  final DateTime publishedAt;
  final bool isPrerelease;
  bool isInstalled;

  CoreSpec({
    required this.type,
    required this.version,
    required this.downloadUrl,
    required this.sha256,
    required this.size,
    required this.publishedAt,
    this.isPrerelease = false,
    this.isInstalled = false,
  });

  factory CoreSpec.fromJson(Map<String, dynamic> json, CoreType type) {
    return CoreSpec(
      type: type,
      version: json['tag_name'] as String? ?? json['version'] as String? ?? '',
      downloadUrl: json['download_url'] as String? ?? '',
      sha256: json['sha256'] as String? ?? '',
      size: json['size'] as int? ?? 0,
      publishedAt:
          DateTime.tryParse(json['published_at'] as String? ?? '') ??
          DateTime.now(),
      isPrerelease: json['prerelease'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'version': version,
      'download_url': downloadUrl,
      'sha256': sha256,
      'size': size,
      'published_at': publishedAt.toIso8601String(),
      'prerelease': isPrerelease,
      'installed': isInstalled,
    };
  }

  /// Версия с префиксом 'v'.
  String get versionWithV => 'v$version';

  /// Человекочитаемое описание версии.
  String get displayLabel {
    final prerelease = isPrerelease ? ' (pre-release)' : '';
    return '${type.label} $versionWithV$prerelease';
  }
}

/// Результат операции с ядром.
class CoreOperationResult {
  final bool success;
  final String? error;
  final CoreSpec? spec;

  const CoreOperationResult({required this.success, this.error, this.spec});

  factory CoreOperationResult.failure(String error) {
    return CoreOperationResult(success: false, error: error);
  }

  factory CoreOperationResult.success(CoreSpec spec) {
    return CoreOperationResult(success: true, spec: spec);
  }
}
