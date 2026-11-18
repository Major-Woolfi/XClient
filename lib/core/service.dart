import 'dart:async';
import 'dart:io';

import 'package:xclient/common/common.dart';
import 'package:xclient/core/core_manager.dart';
import 'package:xclient/core/core_type.dart';
import 'package:xclient/enum/enum.dart';
import 'package:xclient/models/core.dart';
import 'package:flutter/foundation.dart';

import 'desktop/helper_client.dart';
import 'desktop/launcher.dart';
import 'desktop/lifecycle.dart';
import 'desktop/model.dart';
import 'desktop/rpc_client.dart';
import 'desktop/transport.dart';
import 'event.dart';
import 'interface.dart';
import 'method.dart';

class CoreService extends CoreHandlerInterface {
  static CoreService? _instance;

  final DesktopCoreLifecycleController _lifecycle;
  final CoreRpcChannel _rpcClient;
  late final StreamSubscription<DesktopCoreFailure> _crashSubscription;
  Future<CoreLifecycleResult>? _closeOperation;

  factory CoreService() {
    return _instance ??= CoreService._create();
  }

  @visibleForTesting
  static void resetInstance() {
    _instance = null;
  }

  factory CoreService._create() {
    final address = system.isWindows ? windowsPipeName : unixSocketPath;
    final directLauncher = DirectCoreLauncher(
      corePathResolver: _resolveClashBinaryPath,
    );

    final lifecycle = DesktopCoreLifecycle(
      transportFactory: () => IpcCoreTransport(address: address),
      launcherResolver: HelperLauncherResolver(
        hasHelper: system.hasHelperService && !safeModeBuild,
        directLauncher: directLauncher,
        helperLauncher: HelperLauncher(helperClient),
        helperReady: () => helperClient.readiness(),
      ),
      verifyPeerPid: system.isWindows,
    );
    return CoreService._(
      lifecycle: lifecycle,
      rpcClient: CoreRpcClient(lifecycle.transport),
    );
  }

  /// Разрешает путь к бинарнику Clash.Meta через менеджер ядер.
  /// Если версия не установлена - скачивает её автоматически (как для Xray).
  static Future<String> _resolveClashBinaryPath() async {
    final manager = coreBinaryManager;
    final version = await manager.getActiveVersion();
    final path = await manager.getBinaryPath(CoreType.clash, version);
    if (path != null && await File(path).exists()) {
      return path;
    }
    final result = await manager.installCore(
      CoreType.clash,
      version,
      setActive: true,
    );
    if (result.success) {
      final installed = await manager.getBinaryPath(CoreType.clash, version);
      if (installed != null && await File(installed).exists()) {
        return installed;
      }
    }
    throw StateError(
      'Clash.Meta core binary is not installed for version $version. '
      'Install it via the kernel manager first.',
    );
  }

  @visibleForTesting
  CoreService.forTesting({
    required DesktopCoreLifecycleController lifecycle,
    required CoreRpcChannel rpcClient,
  }) : this._(lifecycle: lifecycle, rpcClient: rpcClient);

  CoreService._({
    required DesktopCoreLifecycleController lifecycle,
    required CoreRpcChannel rpcClient,
  }) : _lifecycle = lifecycle,
       _rpcClient = rpcClient {
    _crashSubscription = _lifecycle.crashEvents.listen((failure) {
      coreEventManager.sendEvent(
        CoreEvent(
          type: CoreEventType.crash,
          data: failure.cause?.toString() ?? 'core done',
        ),
      );
    });
  }

  @override
  Future<CoreLifecycleResult> start() => _lifecycle.start();

  @override
  Future<CoreLifecycleResult> restart() => _lifecycle.restart();

  @override
  Future<CoreLifecycleResult> stop() => _lifecycle.stop();

  @override
  Future<CoreLifecycleResult> close() {
    return _closeOperation ??= _close();
  }

  Future<CoreLifecycleResult> _close() async {
    try {
      return await _lifecycle.close();
    } finally {
      await _rpcClient.close();
      await _crashSubscription.cancel();
    }
  }

  @override
  Future<Object?> invokeMethod({
    required CoreMethod method,
    Object? arguments,
    Duration? timeout,
  }) {
    return _rpcClient.invoke(
      method: method,
      arguments: arguments,
      timeout: timeout,
    );
  }
}

final coreService = system.isDesktop ? CoreService() : null;
