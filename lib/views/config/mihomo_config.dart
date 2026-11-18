import 'package:xclient/common/common.dart';
import 'package:xclient/enum/enum.dart';
import 'package:xclient/models/clash_config.dart';
import 'package:xclient/providers/providers.dart';
import 'package:xclient/widgets/widgets.dart';
import 'package:xclient/features/form/map_edit_view.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Настройка ядра Mihomo (Clash.Meta) - конфигуратор.
///
/// Содержит параметры, которые пишутся в профиль Mihomo:
/// порты, логи, LAN, внешний контроллер, хосты, автообновление GEO и т.д.
class MihomoConfigView extends ConsumerWidget {
  const MihomoConfigView({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final appLocalizations = context.appLocalizations;
    final authentication = ref.watch(
      networkSettingProvider.select((state) => state.authentication.enable),
    );
    final externalController = ref.watch(
      patchClashConfigProvider.select(
        (state) => state.externalController == ExternalControllerStatus.open,
      ),
    );
    return BaseScaffold(
      title: appLocalizations.mihomo,
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(
          top: context.sectionsTopPadding,
          bottom: 16 + context.bottomInset,
        ),
        children: [
          generateSection(
            title: appLocalizations.mihomoPorts,
            items: [
              const _MixedPortItem(),
              const _SocksPortItem(),
              const _RedirPortItem(),
              const _TProxyPortItem(),
            ],
          ),
          generateSection(
            title: appLocalizations.mihomoLog,
            items: [const _LogLevelItem()],
          ),
          generateSection(
            title: appLocalizations.mihomoNetwork,
            items: [
              _clashToggle(
                title: (l) => l.allowLan,
                select: (state) => state.allowLan,
                update: (state, value) => state.copyWith(allowLan: value),
              ),
              _clashToggle(
                title: (l) => l.ipv6,
                select: (state) => state.ipv6,
                update: (state, value) => state.copyWith(ipv6: value),
              ),
              _clashToggle(
                title: (l) => l.findProcessMode,
                select: (state) =>
                    state.findProcessMode == FindProcessMode.always,
                update: (state, value) => state.copyWith(
                  findProcessMode: value
                      ? FindProcessMode.always
                      : FindProcessMode.off,
                ),
              ),
              _clashToggle(
                title: (l) => l.unifiedDelay,
                select: (state) => state.unifiedDelay,
                update: (state, value) => state.copyWith(unifiedDelay: value),
              ),
              _clashToggle(
                title: (l) => l.tcpConcurrent,
                select: (state) => state.tcpConcurrent,
                update: (state, value) => state.copyWith(tcpConcurrent: value),
              ),
            ],
          ),
          generateSection(
            title: appLocalizations.mihomoController,
            items: [
              _clashToggle(
                title: (l) => l.externalController,
                select: (state) =>
                    state.externalController == ExternalControllerStatus.open,
                update: (state, value) => state
                    .copyWith(
                      externalController: value
                          ? ExternalControllerStatus.open
                          : ExternalControllerStatus.close,
                    )
                    .ensureControllerSecret(),
              ),
              if (externalController) const _ExternalControllerSecretItem(),
            ],
          ),
          generateSection(
            title: appLocalizations.mihomoHosts,
            items: [const _HostsItem()],
          ),
          generateSection(
            title: appLocalizations.mihomoGeo,
            items: [
              _clashToggle(
                title: (l) => l.geoAutoUpdate,
                select: (state) => state.geoAutoUpdate,
                update: (state, value) => state.copyWith(geoAutoUpdate: value),
              ),
              ConfigOptionsItem<int>(
                title: (l) => l.geoUpdateInterval,
                options: geoUpdateIntervalOptions,
                textBuilder: (value) => '$value ${appLocalizations.hours}',
                selector: patchClashConfigProvider.select(
                  (state) => state.geoUpdateInterval,
                ),
                onChanged: (ref, value) => ref
                    .read(patchClashConfigProvider.notifier)
                    .update(
                      (state) => state.copyWith(geoUpdateInterval: value),
                    ),
              ),
            ],
          ),
          generateSection(
            title: appLocalizations.mihomoDelay,
            items: [const _DelayTestTimeoutItem(), const _TestUrlItem()],
          ),
          if (authentication) ...[
            generateSection(
              title: appLocalizations.authentication,
              items: [
                const _AuthenticationItem(),
                const _AuthenticationAccountItem(),
                const _AuthenticationPasswordItem(),
              ],
            ),
          ],
        ],
      ),
    );
  }

  ConfigToggleItem _clashToggle({
    required ConfigLabel title,
    required bool Function(PatchClashConfig state) select,
    required PatchClashConfig Function(PatchClashConfig state, bool value)
    update,
  }) {
    return ConfigToggleItem(
      title: title,
      selector: patchClashConfigProvider.select(select),
      onChanged: (ref, value) => ref
          .read(patchClashConfigProvider.notifier)
          .update((state) => update(state, value)),
    );
  }
}

/// Смешанный порт (mixed-port).
class _MixedPortItem extends ConsumerWidget {
  const _MixedPortItem();

  @override
  Widget build(BuildContext context, ref) {
    return ConfigTextItem(
      title: (l) => l.mixedPort,
      maxLength: TextInputLimits.port,
      selector: patchClashConfigProvider.select(
        (state) => state.mixedPort.toString(),
      ),
      keyboardType: TextInputType.number,
      normalize: (value) => value.trim(),
      onChanged: (ref, value) {
        ref
            .read(patchClashConfigProvider.notifier)
            .update(
              (state) => state.copyWith(mixedPort: int.tryParse(value) ?? 0),
            );
      },
    );
  }
}

/// SOCKS-порт (socks-port).
class _SocksPortItem extends ConsumerWidget {
  const _SocksPortItem();

  @override
  Widget build(BuildContext context, ref) {
    return ConfigTextItem(
      title: (l) => l.socksPort,
      maxLength: TextInputLimits.port,
      selector: patchClashConfigProvider.select(
        (state) => state.socksPort.toString(),
      ),
      keyboardType: TextInputType.number,
      normalize: (value) => value.trim(),
      onChanged: (ref, value) {
        ref
            .read(patchClashConfigProvider.notifier)
            .update(
              (state) => state.copyWith(socksPort: int.tryParse(value) ?? 0),
            );
      },
    );
  }
}

/// REDIR-порт (redir-port).
class _RedirPortItem extends ConsumerWidget {
  const _RedirPortItem();

  @override
  Widget build(BuildContext context, ref) {
    return ConfigTextItem(
      title: (l) => l.redirPort,
      maxLength: TextInputLimits.port,
      selector: patchClashConfigProvider.select(
        (state) => state.redirPort.toString(),
      ),
      keyboardType: TextInputType.number,
      normalize: (value) => value.trim(),
      onChanged: (ref, value) {
        ref
            .read(patchClashConfigProvider.notifier)
            .update(
              (state) => state.copyWith(redirPort: int.tryParse(value) ?? 0),
            );
      },
    );
  }
}

/// TProxy-порт (tproxy-port).
class _TProxyPortItem extends ConsumerWidget {
  const _TProxyPortItem();

  @override
  Widget build(BuildContext context, ref) {
    return ConfigTextItem(
      title: (l) => l.tProxyPort,
      maxLength: TextInputLimits.port,
      selector: patchClashConfigProvider.select(
        (state) => state.tproxyPort.toString(),
      ),
      keyboardType: TextInputType.number,
      normalize: (value) => value.trim(),
      onChanged: (ref, value) {
        ref
            .read(patchClashConfigProvider.notifier)
            .update(
              (state) => state.copyWith(tproxyPort: int.tryParse(value) ?? 0),
            );
      },
    );
  }
}

/// Уровень логирования (log-level).
class _LogLevelItem extends ConsumerWidget {
  const _LogLevelItem();

  @override
  Widget build(BuildContext context, ref) {
    return ConfigOptionsItem<LogLevel>(
      title: (l) => l.logLevel,
      options: LogLevel.values,
      textBuilder: (logLevel) => logLevel.name,
      selector: patchClashConfigProvider.select((state) => state.logLevel),
      onChanged: (ref, value) => ref
          .read(patchClashConfigProvider.notifier)
          .update((state) => state.copyWith(logLevel: value)),
    );
  }
}

/// Таймаут теста задержки.
class _DelayTestTimeoutItem extends ConsumerWidget {
  const _DelayTestTimeoutItem();

  @override
  Widget build(BuildContext context, ref) {
    return ConfigOptionsItem<int>(
      title: (l) => l.delayTestTimeout,
      options: delayTestTimeoutOptions,
      textBuilder: (value) => '$value ms',
      selector: appSettingProvider.select((state) => state.delayTestTimeout),
      onChanged: (ref, value) => ref
          .read(appSettingProvider.notifier)
          .update((state) => state.copyWith(delayTestTimeout: value)),
    );
  }
}

/// URL для теста задержки (test-url).
class _TestUrlItem extends ConsumerWidget {
  const _TestUrlItem();

  @override
  Widget build(BuildContext context, ref) {
    return ConfigTextItem(
      title: (l) => l.testUrl,
      selector: patchClashConfigProvider.select((state) => state.testUrl),
      normalize: (value) => value.trim(),
      onChanged: (ref, value) => ref
          .read(patchClashConfigProvider.notifier)
          .update((state) => state.copyWith(testUrl: value)),
    );
  }
}

/// Хосты (hosts).
class _HostsItem extends ConsumerWidget {
  const _HostsItem();

  @override
  Widget build(BuildContext context, ref) {
    final appLocalizations = context.appLocalizations;
    final hosts = ref.watch(
      patchClashConfigProvider.select((state) => state.hosts),
    );
    return ListItem.open(
      title: const Text('Hosts'),
      subtitle: Text(
        hosts.isEmpty
            ? appLocalizations.none
            : appLocalizations.itemsCount(hosts.length),
      ),
      widget: MapEditView(
        title: 'Hosts',
        entries: hosts,
        keyMaxLength: TextInputLimits.domain,
        valueMaxLength: TextInputLimits.hostValue,
        titleBuilder: (item) => Text(item.key),
        subtitleBuilder: (item) => Text(item.value),
      ),
      onChanged: (value) {
        if (value is! Map<String, String>) {
          return;
        }
        ref
            .read(patchClashConfigProvider.notifier)
            .update((state) => state.copyWith(hosts: value));
      },
    );
  }
}

/// Секрет внешнего контроллера.
class _ExternalControllerSecretItem extends ConsumerWidget {
  const _ExternalControllerSecretItem();

  @override
  Widget build(BuildContext context, ref) {
    return ConfigTextItem(
      title: (l) => l.externalControllerSecret,
      maxLength: TextInputLimits.password,
      selector: patchClashConfigProvider.select((state) => state.secret),
      normalize: (value) => value.trim(),
      onChanged: (ref, value) => ref
          .read(patchClashConfigProvider.notifier)
          .update((state) => state.copyWith(secret: value)),
    );
  }
}

/// Аутентификация.
class _AuthenticationItem extends ConsumerWidget {
  const _AuthenticationItem();

  @override
  Widget build(BuildContext context, ref) {
    return ConfigToggleItem(
      title: (l) => l.authentication,
      selector: networkSettingProvider.select(
        (state) => state.authentication.enable,
      ),
      onChanged: (ref, value) =>
          ref.read(networkSettingProvider.notifier).update((state) {
            var authentication = state.authentication.copyWith(enable: value);
            if (value && authentication.username.isEmpty) {
              authentication = authentication.copyWith(
                username: generateRandomSecret(8),
                password: generateRandomSecret(16),
              );
            }
            return state.copyWith(authentication: authentication);
          }),
    );
  }
}

/// Имя пользователя аутентификации.
class _AuthenticationAccountItem extends ConsumerWidget {
  const _AuthenticationAccountItem();

  @override
  Widget build(BuildContext context, ref) {
    return ConfigTextItem(
      title: (l) => l.account,
      maxLength: TextInputLimits.userName,
      selector: networkSettingProvider.select(
        (state) => state.authentication.username,
      ),
      normalize: (value) => value.trim().replaceAll(':', ''),
      onChanged: (ref, value) => ref
          .read(networkSettingProvider.notifier)
          .update((state) => state.copyWith.authentication(username: value)),
    );
  }
}

/// Пароль аутентификации.
class _AuthenticationPasswordItem extends ConsumerWidget {
  const _AuthenticationPasswordItem();

  @override
  Widget build(BuildContext context, ref) {
    return ConfigTextItem(
      title: (l) => l.password,
      maxLength: TextInputLimits.password,
      selector: networkSettingProvider.select(
        (state) => state.authentication.password,
      ),
      normalize: (value) => value.trim(),
      onChanged: (ref, value) => ref
          .read(networkSettingProvider.notifier)
          .update((state) => state.copyWith.authentication(password: value)),
    );
  }
}

/// Варианты интервала обновления GEO (часы).
final List<int> geoUpdateIntervalOptions = [1, 6, 12, 24, 48, 72, 168];
