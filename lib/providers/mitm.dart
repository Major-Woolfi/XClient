import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:xclient/common/common.dart';
import 'package:xclient/common/mitm_body.dart';
import 'package:xclient/common/mitm_module.dart';
import 'package:xclient/common/mitm_trust.dart';
import 'package:xclient/enum/enum.dart';
import 'package:xclient/models/models.dart';
import 'package:flutter/foundation.dart' show compute, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' show join;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:rust_api/rust_api.dart' show transcodeCharset;

import 'app.dart';
import 'config.dart';
import 'core.dart';
import 'database.dart';

part 'generated/mitm.g.dart';

const _exchangesRefreshInterval = Duration(seconds: 2);

@Riverpod(keepAlive: true)
class MitmCa extends _$MitmCa {
  @override
  Future<MitmCertificate?> build() {
    return ref.read(coreHandlerProvider).getMitmCertificate();
  }

  Future<void> generate() async {
    final certificate = await ref
        .read(coreHandlerProvider)
        .generateMitmCertificate();
    if (!ref.mounted) {
      return;
    }
    state = AsyncData(certificate);
  }
}

@Riverpod(keepAlive: true)
MitmTrustStore? mitmTrustStore(Ref ref) => mitmTrustStoreForPlatform();

/// Доверяет ли это устройство ЦС. Проверка фиксирует ЦС, который нашла
/// доверенным - именно с ним ядро расшифровывает HTTPS.
@Riverpod(keepAlive: true)
class MitmTrustState extends _$MitmTrustState {
  @override
  Future<MitmTrustCheck> build() async {
    return _check(await ref.watch(mitmCaProvider.future));
  }

  Future<MitmTrustCheck> _check(MitmCertificate? ca) async {
    final store = ref.read(mitmTrustStoreProvider);
    final MitmTrustCheck check;
    if (ca == null) {
      check = const MitmTrustCheck(MitmTrust.notGenerated);
    } else if (store == null) {
      check = const MitmTrustCheck(MitmTrust.notInstalled);
    } else {
      final core = ref.read(coreHandlerProvider);
      check = await store.check(
        ca,
        () => core.issueMitmCertificate(mitmCheckHost),
      );
    }
    if (ref.mounted) {
      _record(ca, check);
    }
    return check;
  }

  void _record(MitmCertificate? ca, MitmTrustCheck check) {
    final trusted = check.trust == MitmTrust.ready ? ca?.fingerprint : null;
    if (ref.read(patchClashConfigProvider).mitm.trustedFingerprint == trusted) {
      return;
    }
    ref
        .read(patchClashConfigProvider.notifier)
        .update(
          (state) => state.copyWith(
            mitm: state.mitm.copyWith(trustedFingerprint: trusted),
          ),
        );
  }

  Future<void>? _refreshing;

  /// Вызовы во время проверки делят её, поскольку каждая проверка запускает
  /// инструменты доверия платформы.
  Future<void> refresh() {
    if (state.isLoading) {
      return future.then((_) {}, onError: (_) {});
    }
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  Future<void> _refresh() async {
    final next = await AsyncValue.guard(
      () async => _check(await ref.read(mitmCaProvider.future)),
    );
    if (ref.mounted) {
      state = next;
    }
  }

  Future<MitmInstallOutcome?> install() async {
    final ca = await ref.read(mitmCaProvider.future);
    final store = ref.read(mitmTrustStoreProvider);
    if (ca == null || store == null || ref.read(safeModeProvider)) {
      return null;
    }
    final MitmInstallOutcome outcome;
    try {
      outcome = await store.install(ca);
    } finally {
      if (store is AndroidMitmTrustStore && ref.mounted) {
        ref.invalidate(rootAccessProvider);
      }
    }
    if (outcome == MitmInstallOutcome.installed ||
        outcome == MitmInstallOutcome.untilReboot) {
      await refresh();
    }
    return outcome;
  }

  /// False, когда старый ЦС остаётся в хранилище доверия для пользователя,
  /// чтобы удалить, так как безопасный режим всегда оставляет его.
  Future<bool> regenerate() async {
    final old = await ref.read(mitmCaProvider.future);
    final store = ref.read(mitmTrustStoreProvider);
    final trust = state.value?.trust;
    var removed = true;
    if (old != null &&
        store != null &&
        (trust == MitmTrust.ready || trust == MitmTrust.untrusted)) {
      try {
        removed = !ref.read(safeModeProvider) && await store.remove(old);
      } catch (error) {
        commonPrint.log(
          'Removing the old MITM certificate failed: ${compactError(error)}',
          logLevel: LogLevel.warning,
        );
        removed = false;
      }
      if (store is AndroidMitmTrustStore && ref.mounted) {
        ref.invalidate(rootAccessProvider);
      }
    }
    await ref.read(mitmCaProvider.notifier).generate();
    return removed;
  }
}

/// Снова загружается пока показан, пока соединение не закроется и ни один из
/// его запросов не будет в ожидании.
@riverpod
Future<MitmExchangeList> mitmExchanges(Ref ref, String connectionId) async {
  final list = await ref
      .read(coreHandlerProvider)
      .getMitmExchanges(connectionId);
  final settled =
      list.closed && !list.exchanges.any((exchange) => exchange.pending);
  if (!settled && ref.mounted) {
    final timer = Timer(_exchangesRefreshInterval, ref.invalidateSelf);
    ref.onDispose(timer.cancel);
  }
  return list;
}

@riverpod
Future<MitmExchange?> mitmExchange(Ref ref, int id) async {
  final exchange = await ref.read(coreHandlerProvider).getMitmExchange(id);
  if (exchange != null && exchange.pending && ref.mounted) {
    final timer = Timer(_exchangesRefreshInterval, ref.invalidateSelf);
    ref.onDispose(timer.cancel);
  }
  return exchange;
}

@riverpod
Future<MitmBodyContent?> mitmBody(
  Ref ref,
  int id, {
  required bool response,
  required String contentType,
}) async {
  final body = await ref
      .read(coreHandlerProvider)
      .getMitmBody(id, response: response);
  if (body == null) {
    return null;
  }
  final content = await compute(readMitmBody, (body, contentType));
  if (content.charset.isEmpty) {
    return content;
  }
  final Uint8List? utf8Bytes;
  try {
    utf8Bytes = await mitmCharsetTranscoder(
      bytes: content.bytes,
      label: content.charset,
      lossy: content.truncated,
    );
  } catch (error) {
    commonPrint.log('Reading ${content.charset} failed: $error');
    return content;
  }
  if (utf8Bytes == null) {
    return content;
  }
  return compute(readMitmCharsetText, (content, utf8Bytes, contentType));
}

typedef MitmCharsetTranscoder =
    Future<Uint8List?> Function({
      required List<int> bytes,
      required String label,
      required bool lossy,
    });

@visibleForTesting
MitmCharsetTranscoder mitmCharsetTranscoder = transcodeCharset;

/// Был ли пользователь предупреждён в этом запуске, что может нести
/// скопированный или экспортированный запрос.
@Riverpod(keepAlive: true)
class MitmExportWarned extends _$MitmExportWarned {
  @override
  bool build() => false;

  void accept() => state = true;
}

/// Почему ядро пропускает каждое из имён хостов пользователя, по строкам.
@riverpod
Future<Map<String, String>> mitmHostnameIssues(Ref ref) async {
  final hostname = ref.watch(
    patchClashConfigProvider.select((state) => state.mitm.hostname),
  );
  final issues = await _issuesOf(ref, MitmRules(hostname: hostname));
  return issues[MitmList.hostname] ?? const {};
}

Future<Map<MitmList, Map<String, String>>> _issuesOf(
  Ref ref,
  MitmRules mitm,
) async {
  final issues = await ref.read(coreHandlerProvider).validateMitm(mitm);
  return {
    for (final MapEntry(key: list, value: lines) in issues.entries)
      list: {
        for (final MapEntry(key: index, value: issue) in lines.entries)
          mitm.linesOf(list)[index]: issue,
      },
  };
}

typedef MitmModuleDetails = ({
  MitmModuleContent content,
  Map<MitmList, Map<String, String>> issues,
});

MitmModuleContent _parseModuleSource(MitmModuleSource source) =>
    parseMitmModule(
      source.content,
      values: source.arguments,
      resources: source.resources,
    );

/// Null, пока содержимое модуля не на диске.
@riverpod
Future<MitmModuleDetails?> mitmModuleDetails(Ref ref, int id) async {
  final module = ref.watch(
    mitmModulesProvider.select(
      (state) => state.value?.firstWhereOrNull((item) => item.id == id),
    ),
  );
  if (module == null) {
    return null;
  }
  final file = File(join(await appPath.mitmModulesDirPath, module.fileName));
  if (!await file.exists()) {
    return null;
  }
  final content = await compute(
    _parseModuleSource,
    MitmModuleSource(
      content: await file.readAsString(),
      arguments: module.arguments,
      resources: module.resources,
    ),
  );
  return (content: content, issues: await _issuesOf(ref, content.mitm));
}
