part of '../action.dart';

@Riverpod(keepAlive: true)
class GeoResourceAction extends _$GeoResourceAction {
  /// Каждое ручное обновление объявляет об успехе; неудача всегда показывается.
  final _manualUpdates = <GeoResource, bool>{};
  final _operations = <GeoResource, int>{};

  CoreController get _core => ref.read(coreHandlerProvider);

  @override
  void build() {
    ref.listen(coreStatusProvider, (_, next) {
      if (next != CoreStatus.connected) {
        _manualUpdates.clear();
        _operations.clear();
      }
    });
  }

  int _startUpdating(GeoResource geoResource) {
    return _operations.putIfAbsent(
      geoResource,
      () => ref
          .read(updatingKeysProvider.notifier)
          .start(geoResource.updatingKey, scope: UpdatingScope.core),
    );
  }

  void _stopUpdating(GeoResource geoResource, [int? operation]) {
    final current = _operations[geoResource];
    if (current == null || (operation != null && current != operation)) {
      return;
    }
    _operations.remove(geoResource);
    ref
        .read(updatingKeysProvider.notifier)
        .stop(geoResource.updatingKey, current);
  }

  /// Завершается, когда Core принял обновление, а не когда оно закончилось.
  /// Завершение приходит как событие geo-update через [handleCoreUpdate];
  /// звёнувшие вызовы следят за очисткой ключа в [isUpdatingProvider].
  /// Запрос, который Core отклонил, оставляет уже запущенное обновление как было.
  Future<void> updateGeoResource(
    GeoResource geoResource, {
    bool announceSuccess = true,
  }) async {
    final running = _operations.containsKey(geoResource);
    final previous = _manualUpdates[geoResource];
    _manualUpdates[geoResource] = announceSuccess;
    final operation = _startUpdating(geoResource);
    try {
      await _core.updateGeoData(geoResource.name);
    } catch (_) {
      if (previous != null) {
        _manualUpdates[geoResource] = previous;
      } else {
        _manualUpdates.remove(geoResource);
      }
      if (!running) {
        _stopUpdating(geoResource, operation);
      }
      rethrow;
    }
  }

  void handleCoreUpdate(
    String geoType,
    bool updating,
    bool skipped,
    String? error,
  ) {
    final geoResource = GeoResource.fromJson(geoType.toLowerCase());
    final announceSuccess = updating
        ? null
        : _manualUpdates.remove(geoResource);
    if (announceSuccess != null && error != null && error.isNotEmpty) {
      dialogs.showBanner(error, level: BannerLevel.error);
    } else if (announceSuccess == true) {
      final l10n = currentAppLocalizations;
      final message = skipped
          ? l10n.geoSkipped(geoResource.name)
          : l10n.geoUpdated(geoResource.name);
      dialogs.showBanner(message);
    }
    if (updating) {
      _startUpdating(geoResource);
    } else {
      _stopUpdating(geoResource);
    }
  }

  void updateGeoResourceUrl(GeoResource geoResource, String newUrl) {
    if (!newUrl.isUrl) {
      throw ArgumentError.value(newUrl, 'newUrl', 'Not a valid URL');
    }
    ref.read(patchClashConfigProvider.notifier).update((state) {
      return state.copyWith(geoXUrl: {...state.geoXUrl, geoResource: newUrl});
    });
  }
}
