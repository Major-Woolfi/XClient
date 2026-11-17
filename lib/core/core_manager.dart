import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:xclient/common/common.dart';
import 'package:xclient/enum/enum.dart';

import 'core_type.dart';

/// Управление бинарниками ядер: скачивание, версия, переключение, автообновление.
///
/// Поддерживает несколько ядер (Clash.Meta, Xray-core) независимо от версии
/// приложения. Каждое ядро хранится в отдельной директории в home-директории
/// приложения.
class CoreBinaryManager {
  static CoreBinaryManager? _instance;
  factory CoreBinaryManager() => _instance ??= CoreBinaryManager._internal();
  CoreBinaryManager._internal();

  static void resetInstance() {
    _instance = null;
  }

  /// Текущее активное ядро.
  CoreType get activeCoreType => _activeCoreType;

  CoreType _activeCoreType = CoreType.clash;

  /// Установленные версии ядер (type -> version -> spec).
  final Map<CoreType, Map<String, CoreSpec>> _installed = {};

  /// Все известные версии (из кэша или сети).
  final Map<CoreType, List<CoreSpec>> _available = {};

  final Dio _dio = Dio();

  /// Путь к директории ядер.
  Future<String> get _coresDir async {
    final home = await appPath.homeDirPath;
    final dir = Directory(p.join(home, 'cores'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }

  /// Директория конкретного ядра и версии.
  Future<String> _coreDir(CoreType type, String version) async {
    final coresDir = await _coresDir;
    final dir = Directory(p.join(coresDir, type.storageDir, version));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }

  /// Путь к исполняемому файлу ядра.
  Future<String> _coreBinaryPath(CoreType type, String version) async {
    final dir = await _coreDir(type, version);
    return p.join(dir, '${type.binaryName}${appPath.executableExtension}');
  }

  /// Путь к текущему активному бинарнику.
  Future<String> get activeBinaryPath async {
    final version = await getActiveVersion();
    return _coreBinaryPath(_activeCoreType, version);
  }

  /// Текущая версия активного ядра.
  Future<String> getActiveVersion() async {
    final prefs = await preferences.store;
    final key = 'core_version_${_activeCoreType.name}';
    return prefs?.getString(key) ?? _defaultVersion(_activeCoreType);
  }

  /// Версия по умолчанию для типа ядра.
  String _defaultVersion(CoreType type) {
    switch (type) {
      case CoreType.clash:
        return '1.19.33';
      case CoreType.xray:
        return '1.8.1';
    }
  }

  /// Сохранить активный тип ядра и версию.
  Future<void> setActiveCore(CoreType type, {String? version}) async {
    final prefs = await preferences.store;
    await prefs?.setString('active_core_type', type.name);
    _activeCoreType = type;
    final ver =
        version ??
        await getLatestInstalledVersion(type) ??
        _defaultVersion(type);
    await prefs?.setString('core_version_${type.name}', ver);
  }

  /// Получить сохранённый тип ядра.
  Future<CoreType> getSavedCoreType() async {
    final prefs = await preferences.store;
    final name = prefs?.getString('active_core_type') ?? 'clash';
    return switch (name) {
      'xray' => CoreType.xray,
      _ => CoreType.clash,
    };
  }

  /// Инициализация: загрузить сохранённые настройки и список установленных ядер.
  Future<void> init() async {
    _activeCoreType = await getSavedCoreType();
    await _scanInstalled();
    await loadAvailableVersions();
  }

  /// Сканировать установленные ядра в файловой системе.
  Future<void> _scanInstalled() async {
    _installed.clear();
    for (final type in CoreType.values) {
      _installed[type] = {};
    }

    final coresDir = await _coresDir;
    if (!await Directory(coresDir).exists()) return;

    for (final type in CoreType.values) {
      final typeDir = Directory(p.join(coresDir, type.storageDir));
      if (!await typeDir.exists()) continue;

      final versions = await typeDir.list().toList();
      for (final versionDir in versions) {
        if (versionDir is! Directory) continue;
        final version = p.basename(versionDir.path);
        final binaryPath = p.join(
          versionDir.path,
          '${type.binaryName}${appPath.executableExtension}',
        );
        if (await File(binaryPath).exists()) {
          _installed[type]![version] = CoreSpec(
            type: type,
            version: version,
            downloadUrl: '',
            sha256: '',
            size: await File(binaryPath).length(),
            publishedAt: DateTime.now(),
            isInstalled: true,
          );
        }
      }
    }
  }

  /// Загрузить список доступных версий из GitHub API.
  Future<List<CoreSpec>> loadAvailableVersions({CoreType? type}) async {
    final types = type != null ? [type] : CoreType.values;
    final result = <CoreSpec>[];

    for (final t in types) {
      try {
        final url = '${githubApiUrl(t.repo)}/releases?per_page=20';
        final response = await _dio.get(url);
        if (response.statusCode != 200) continue;

        final List<dynamic> jsonList = response.data;
        final specs = <CoreSpec>[];
        for (final json in jsonList) {
          if (json is! Map<String, dynamic>) continue;
          final spec = CoreSpec.fromJson(json, t);
          spec.isInstalled = _installed[t]?.containsKey(spec.version) ?? false;
          specs.add(spec);
        }
        specs.sort((a, b) {
          final aParts = a.version.split('.').map(int.tryParse).toList();
          final bParts = b.version.split('.').map(int.tryParse).toList();
          for (int i = 0; i < 3; i++) {
            final av = aParts[i] ?? 0;
            final bv = bParts[i] ?? 0;
            if (av != bv) return bv.compareTo(av);
          }
          return 0;
        });
        _available[t] = specs;
        result.addAll(specs);
      } catch (e) {
        commonPrint.log(
          'Failed to load versions for ${t.label}: $e',
          logLevel: LogLevel.warning,
        );
      }
    }

    return result;
  }

  /// Получить доступные версии для типа ядра.
  List<CoreSpec> getAvailableVersions(CoreType type) {
    return _available[type] ?? const [];
  }

  /// Получить установленные версии для типа ядра.
  List<CoreSpec> getInstalledVersions(CoreType type) {
    return _installed[type]?.values.toList() ?? const [];
  }

  /// Получить последнюю установленную версию.
  Future<String?> getLatestInstalledVersion(CoreType type) async {
    final installed = getInstalledVersions(type);
    if (installed.isEmpty) return null;
    installed.sort((a, b) {
      final aParts = a.version.split('.').map(int.tryParse).toList();
      final bParts = b.version.split('.').map(int.tryParse).toList();
      for (int i = 0; i < 3; i++) {
        final av = aParts[i] ?? 0;
        final bv = bParts[i] ?? 0;
        if (av != bv) return bv.compareTo(av);
      }
      return 0;
    });
    return installed.first.version;
  }

  /// Скачать и установить ядро.
  Future<CoreOperationResult> installCore(
    CoreType type,
    String version, {
    bool setActive = false,
  }) async {
    // Проверяем, не установлено ли уже
    if (_installed[type]?.containsKey(version) == true) {
      if (setActive) {
        await setActiveCore(type, version: version);
      }
      return CoreOperationResult.success(_installed[type]![version]!);
    }

    // Находим версию в доступных
    final available = getAvailableVersions(type);
    final spec = available.firstWhere(
      (s) => s.version == version,
      orElse: () =>
          throw Exception('Version $version not available for ${type.label}'),
    );

    if (spec.downloadUrl.isEmpty) {
      return CoreOperationResult.failure(
        'No download URL for version $version',
      );
    }

    try {
      final dir = await _coreDir(type, version);
      final binaryPath = p.join(
        dir,
        '${type.binaryName}${appPath.executableExtension}',
      );
      final tempPath = '$binaryPath.tmp';

      // Скачиваем
      commonPrint.log(
        'Downloading ${type.label} $version from ${spec.downloadUrl}',
      );
      await _dio.download(
        spec.downloadUrl,
        tempPath,
        onReceiveProgress: (received, total) {
          // Прогресс можно отслеживать через провайдер
        },
      );

      // Проверяем SHA256 если указан
      if (spec.sha256.isNotEmpty) {
        final bytes = File(tempPath).readAsBytesSync();
        final hash = sha256.convert(bytes).toString();
        if (hash.toLowerCase() != spec.sha256.toLowerCase()) {
          await File(tempPath).delete();
          return CoreOperationResult.failure('SHA256 mismatch for $version');
        }
      }

      await File(tempPath).rename(binaryPath);

      final installedSpec = CoreSpec(
        type: type,
        version: version,
        downloadUrl: spec.downloadUrl,
        sha256: spec.sha256,
        size: spec.size,
        publishedAt: spec.publishedAt,
        isPrerelease: spec.isPrerelease,
        isInstalled: true,
      );
      _installed[type] ??= {};
      _installed[type]![version] = installedSpec;

      if (setActive) {
        await setActiveCore(type, version: version);
      }

      return CoreOperationResult.success(installedSpec);
    } catch (e) {
      return CoreOperationResult.failure('Failed to install $version: $e');
    }
  }

  /// Удалить установленную версию ядра.
  Future<bool> uninstallCore(CoreType type, String version) async {
    // Нельзя удалить активное ядро
    final activeVersion = await getActiveVersion();
    if (_activeCoreType == type && activeVersion == version) {
      return false;
    }

    final dir = await _coreDir(type, version);
    if (await Directory(dir).exists()) {
      await Directory(dir).delete(recursive: true);
      _installed[type]?.remove(version);
      return true;
    }
    return false;
  }

  /// Переключиться на другое ядро (без скачивания, если уже установлено).
  Future<CoreOperationResult> switchCore(
    CoreType type, {
    String? version,
  }) async {
    final ver =
        version ??
        await getLatestInstalledVersion(type) ??
        _defaultVersion(type);

    if (!_installed.containsKey(type) || !_installed[type]!.containsKey(ver)) {
      // Пытаемся установить
      final result = await installCore(type, ver, setActive: true);
      return result;
    }

    await setActiveCore(type, version: ver);
    return CoreOperationResult.success(_installed[type]![ver]!);
  }

  /// Получить путь к бинарнику для заданного типа и версии.
  Future<String?> getBinaryPath(CoreType type, String version) async {
    final spec = _installed[type]?[version];
    if (spec == null) return null;
    final path = await _coreBinaryPath(type, version);
    if (await File(path).exists()) return path;
    return null;
  }

  /// Проверить обновления для активного ядра.
  Future<List<CoreSpec>> checkForUpdates(CoreType type) async {
    await loadAvailableVersions(type: type);
    final installed = getInstalledVersions(type);
    final available = getAvailableVersions(type);

    final updates = <CoreSpec>[];
    for (final inst in installed) {
      final latest = available.firstWhere(
        (a) => a.version == inst.version,
        orElse: () => inst,
      );
      if (latest.version != inst.version) {
        updates.add(latest);
      }
    }
    return updates;
  }

  /// Автоопределение типа ядра по ссылке.
  CoreType detectCoreTypeFromLink(String link) {
    for (final type in CoreType.values) {
      if (type.acceptsLink(link)) return type;
    }
    return CoreType.clash;
  }

  /// Автоопределение типа ядра по конфигу.
  CoreType detectCoreTypeFromConfig(String content) {
    for (final type in CoreType.values) {
      if (type.acceptsConfig(content)) return type;
    }
    return CoreType.clash;
  }
}

final coreBinaryManager = CoreBinaryManager();
