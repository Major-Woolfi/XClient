import 'package:xclient/core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Состояние загрузки одного ядра.
enum CoreKernelStatus { idle, installing, installed, error }

/// Модель ядра для отображения в UI.
class CoreKernelModel {
  final CoreType type;
  final CoreSpec spec;
  final CoreKernelStatus status;
  final double progress;

  const CoreKernelModel({
    required this.type,
    required this.spec,
    this.status = CoreKernelStatus.idle,
    this.progress = 0.0,
  });

  CoreKernelModel copyWith({
    CoreType? type,
    CoreSpec? spec,
    CoreKernelStatus? status,
    double? progress,
  }) {
    return CoreKernelModel(
      type: type ?? this.type,
      spec: spec ?? this.spec,
      status: status ?? this.status,
      progress: progress ?? this.progress,
    );
  }

  bool get isInstalled => status == CoreKernelStatus.installed;
  bool get isInstalling => status == CoreKernelStatus.installing;
  bool get hasError => status == CoreKernelStatus.error;
}

/// Состояние менеджера ядер.
class CoreKernelState {
  final CoreType activeType;
  final String activeVersion;
  final Map<CoreType, List<CoreKernelModel>> models;
  final Map<CoreType, List<CoreSpec>> available;

  const CoreKernelState({
    required this.activeType,
    required this.activeVersion,
    this.models = const {},
    this.available = const {},
  });

  CoreKernelModel? getActiveModel() {
    return models[activeType]?.firstWhere(
      (m) => m.spec.version == activeVersion,
      orElse: () => throw StateError('Model not found'),
    );
  }

  CoreKernelState copyWith({
    CoreType? activeType,
    String? activeVersion,
    Map<CoreType, List<CoreKernelModel>>? models,
    Map<CoreType, List<CoreSpec>>? available,
  }) {
    return CoreKernelState(
      activeType: activeType ?? this.activeType,
      activeVersion: activeVersion ?? this.activeVersion,
      models: models ?? this.models,
      available: available ?? this.available,
    );
  }
}

/// Менеджер ядер (состояние + операции).
class CoreKernelNotifier extends ChangeNotifier {
  CoreKernelState _state = const CoreKernelState(
    activeType: CoreType.clash,
    activeVersion: '1.19.33',
  );

  CoreKernelState get state => _state;

  set state(CoreKernelState value) {
    _state = value;
    notifyListeners();
  }

  /// Инициализация из сохранённых настроек.
  Future<void> init() async {
    final manager = coreBinaryManager;
    final type = await manager.getSavedCoreType();
    final version = await manager.getActiveVersion();
    await _loadModels(type);
    state = state.copyWith(activeType: type, activeVersion: version);
  }

  /// Загрузить модели для типа ядра.
  Future<void> _loadModels(CoreType type) async {
    final manager = coreBinaryManager;
    await manager.loadAvailableVersions(type: type);

    final installed = <CoreKernelModel>[];
    for (final spec in manager.getInstalledVersions(type)) {
      installed.add(
        CoreKernelModel(
          type: type,
          spec: spec,
          status: CoreKernelStatus.installed,
        ),
      );
    }

    final available = <CoreKernelModel>[];
    for (final spec in manager.getAvailableVersions(type)) {
      if (spec.isInstalled) continue;
      available.add(
        CoreKernelModel(type: type, spec: spec, status: CoreKernelStatus.idle),
      );
    }

    state = state.copyWith(
      models: {
        ...state.models,
        type: [...installed, ...available],
      },
    );
  }

  /// Установить (скачать) версию ядра.
  Future<void> install(CoreType type, String version) async {
    final manager = coreBinaryManager;

    state = state.copyWith(
      models: {
        ...state.models,
        type: [
          for (final m in state.models[type] ?? const [])
            if (m.spec.version == version)
              m.copyWith(status: CoreKernelStatus.installing, progress: 0.0)
            else
              m,
        ],
      },
    );

    try {
      final result = await manager.installCore(type, version, setActive: true);

      if (result.success && result.spec != null) {
        await _loadModels(type);
        state = state.copyWith(activeType: type, activeVersion: version);
      } else {
        state = state.copyWith(
          models: {
            ...state.models,
            type: [
              for (final m in state.models[type] ?? const [])
                if (m.spec.version == version)
                  m.copyWith(status: CoreKernelStatus.error)
                else
                  m,
            ],
          },
        );
      }
    } catch (e) {
      state = state.copyWith(
        models: {
          ...state.models,
          type: [
            for (final m in state.models[type] ?? const [])
              if (m.spec.version == version)
                m.copyWith(status: CoreKernelStatus.error)
              else
                m,
          ],
        },
      );
    }
  }

  /// Переключиться на установленное ядро.
  Future<void> switchTo(CoreType type, String version) async {
    final result = await coreBinaryManager.switchCore(type, version: version);
    if (result.success) {
      await _loadModels(type);
      state = state.copyWith(activeType: type, activeVersion: version);
    }
  }

  /// Удалить версию ядра.
  Future<void> uninstall(CoreType type, String version) async {
    final success = await coreBinaryManager.uninstallCore(type, version);
    if (success) {
      await _loadModels(type);
      if (state.activeType == type && state.activeVersion == version) {
        final clashVersion =
            await coreBinaryManager.getLatestInstalledVersion(CoreType.clash) ??
            '1.19.33';
        state = state.copyWith(
          activeType: CoreType.clash,
          activeVersion: clashVersion,
        );
        await coreBinaryManager.switchCore(
          CoreType.clash,
          version: clashVersion,
        );
      }
    }
  }

  /// Проверить обновления.
  Future<void> checkUpdates(CoreType type) async {
    final updates = await coreBinaryManager.checkForUpdates(type);
    state = state.copyWith(
      models: {
        ...state.models,
        type: [
          for (final m in state.models[type] ?? const [])
            if (updates.any((u) => u.version == m.spec.version))
              m.copyWith(status: CoreKernelStatus.idle)
            else
              m,
        ],
      },
    );
  }
}

final coreKernelProvider = Provider<CoreKernelNotifier>((ref) {
  return CoreKernelNotifier();
});

/// Провайдер активного типа ядра.
final activeCoreTypeProvider = Provider<CoreType>((ref) {
  return ref.watch(coreKernelProvider).state.activeType;
});

/// Провайдер активной версии ядра.
final activeCoreVersionProvider = Provider<String>((ref) {
  return ref.watch(coreKernelProvider).state.activeVersion;
});

/// Провайдер моделей ядер для типа.
final coreKernelModelsProvider =
    Provider.family<List<CoreKernelModel>, CoreType>((ref, type) {
      return ref.watch(coreKernelProvider).state.models[type] ?? const [];
    });
