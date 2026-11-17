part of '../action.dart';

@Riverpod(keepAlive: true)
class StoreAction extends _$StoreAction {
  CoreController get _core => ref.read(coreHandlerProvider);

  @override
  void build() {}

  Future<void> shakingStore() async {
    // Списки пропускают строки, которые не могут прочитать, а их файлы должны
    // сохраниться, и таблицы могут ещё не содержать оптимистичной записи.
    final profileIds = {
      ...ref.read(profilesProvider).map((item) => item.id),
      ...await database.profilesDao.ids().get(),
    };
    final scripts = await ref.read(scriptsProvider.future);
    final scriptIds = {
      ...scripts.map((item) => item.id),
      ...await database.scriptsDao.ids().get(),
    };
    final providerFileNames = await database.clashProvidersDao
        .fileNames()
        .get();
    final pathsToDelete = await shakingProfileTask((
      profileIds: profileIds,
      scriptIds: scriptIds,
      providerFileNames: providerFileNames,
    ));
    await Future.wait(pathsToDelete.map(safeDeletePath));
  }

  void savePreferencesDebounce() {
    debouncer.call(FunctionTag.savePreferences, () async {
      await preferences.saveConfig(ref.read(configProvider));
    });
  }

  Future handleClear() async {
    debouncer.cancel(FunctionTag.savePreferences);
    final profileIds = ref
        .read(profilesProvider)
        .map((item) => item.id)
        .toSet();
    final providersDir = Directory(await appPath.getProvidersRootPath());
    if (await providersDir.exists()) {
      await for (final entity in providersDir.list(followLinks: false)) {
        if (entity is! Directory) continue;
        final profileId = int.tryParse(basename(entity.path));
        if (profileId != null && profileId > 0) {
          profileIds.add(profileId);
        }
      }
    }
    await Future.wait(
      profileIds.map((profileId) async {
        try {
          await _core.clearEffect(profileId);
        } catch (error) {
          commonPrint.log(
            'clearEffect($profileId) failed: $error',
            logLevel: LogLevel.warning,
          );
        }
      }),
    );
    await clearAppData();
    unawaited(ref.read(systemActionProvider.notifier).handleExit(false));
  }
}
