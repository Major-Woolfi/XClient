import 'package:xclient/core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum CoreKernelStatus { idle, installing, installed, error }

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

class CoreKernelState {
  final CoreType activeType;
  final String activeVersion;
  final Map<CoreType, List<CoreKernelModel>> models;

  const CoreKernelState({
    required this.activeType,
    required this.activeVersion,
    this.models = const {},
  });

  CoreKernelModel? get activeModel {
    for (final model in models[activeType] ?? const <CoreKernelModel>[]) {
      if (model.spec.version == activeVersion) {
        return model;
      }
    }
    return null;
  }

  CoreKernelState copyWith({
    CoreType? activeType,
    String? activeVersion,
    Map<CoreType, List<CoreKernelModel>>? models,
  }) {
    return CoreKernelState(
      activeType: activeType ?? this.activeType,
      activeVersion: activeVersion ?? this.activeVersion,
      models: models ?? this.models,
    );
  }
}

class CoreKernelNotifier extends Notifier<CoreKernelState> {
  @override
  CoreKernelState build() {
    final type = coreBinaryManager.activeCoreType;
    final version = _installedVersion(type);
    Future.microtask(init);
    return CoreKernelState(
      activeType: type,
      activeVersion: version,
      models: {for (final type in CoreType.values) type: _modelsOf(type)},
    );
  }

  Future<void> init() async {
    final type = await coreBinaryManager.getSavedCoreType();
    final version = await coreBinaryManager.getActiveVersion();
    state = state.copyWith(
      activeType: type,
      activeVersion: version,
      models: {for (final type in CoreType.values) type: _modelsOf(type)},
    );
  }

  Future<void> install(CoreType type, String version) async {
    _updateModel(type, version, status: CoreKernelStatus.installing);
    try {
      final result = await coreBinaryManager.installCore(
        type,
        version,
        setActive: true,
      );
      if (result.success) {
        _reload(type);
        state = state.copyWith(activeType: type, activeVersion: version);
      } else {
        _updateModel(type, version, status: CoreKernelStatus.error);
      }
    } catch (_) {
      _updateModel(type, version, status: CoreKernelStatus.error);
    }
  }

  Future<void> switchTo(CoreType type, String version) async {
    final result = await coreBinaryManager.switchCore(type, version: version);
    if (result.success) {
      _reload(type);
      state = state.copyWith(activeType: type, activeVersion: version);
    }
  }

  Future<void> uninstall(CoreType type, String version) async {
    if (!await coreBinaryManager.uninstallCore(type, version)) {
      return;
    }
    _reload(type);
    if (state.activeType == type && state.activeVersion == version) {
      final fallback =
          await coreBinaryManager.getLatestInstalledVersion(CoreType.clash) ??
          _defaultVersion(CoreType.clash);
      await coreBinaryManager.switchCore(CoreType.clash, version: fallback);
      state = state.copyWith(
        activeType: CoreType.clash,
        activeVersion: fallback,
      );
    }
  }

  void _reload(CoreType type) {
    state = state.copyWith(models: {...state.models, type: _modelsOf(type)});
  }

  void _updateModel(
    CoreType type,
    String version, {
    required CoreKernelStatus status,
    double? progress,
  }) {
    final models = state.models[type] ?? const <CoreKernelModel>[];
    state = state.copyWith(
      models: {
        ...state.models,
        type: [
          for (final model in models)
            if (model.spec.version == version)
              model.copyWith(status: status, progress: progress)
            else
              model,
        ],
      },
    );
  }

  List<CoreKernelModel> _modelsOf(CoreType type) {
    final installed = coreBinaryManager
        .getInstalledVersions(type)
        .map(
          (spec) => CoreKernelModel(
            type: type,
            spec: spec,
            status: CoreKernelStatus.installed,
          ),
        );
    final available = coreBinaryManager
        .getAvailableVersions(type)
        .where((spec) => !spec.isInstalled)
        .map((spec) => CoreKernelModel(type: type, spec: spec));
    return [...installed, ...available];
  }

  String _installedVersion(CoreType type) {
    final installed = coreBinaryManager.getInstalledVersions(type);
    return installed.isEmpty ? '' : installed.first.version;
  }

  String _defaultVersion(CoreType type) {
    return switch (type) {
      CoreType.clash => '1.19.33',
      CoreType.xray => '1.8.1',
    };
  }
}

final coreKernelProvider =
    NotifierProvider<CoreKernelNotifier, CoreKernelState>(
      CoreKernelNotifier.new,
    );

final activeCoreTypeProvider = Provider<CoreType>((ref) {
  return ref.watch(coreKernelProvider).activeType;
});

final activeCoreVersionProvider = Provider<String>((ref) {
  return ref.watch(coreKernelProvider).activeVersion;
});

final coreKernelModelsProvider =
    Provider.family<List<CoreKernelModel>, CoreType>((ref, type) {
      return ref.watch(coreKernelProvider).models[type] ?? const [];
    });
