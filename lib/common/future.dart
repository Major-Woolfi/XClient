import 'dart:async';

import 'package:xclient/common/print.dart';
import 'package:xclient/enum/enum.dart';
import 'package:xclient/ui/ui.dart';
import 'package:flutter/foundation.dart';

extension FutureExt<T> on Future<T> {
  Future<T> withTimeout({
    Duration? timeout,
    String? tag,
    VoidCallback? onLast,
    FutureOr<T> Function()? onTimeout,
  }) {
    final realTimeout = timeout ?? const Duration(minutes: 3);
    final cleanupTimer = onLast == null
        ? null
        : Timer(realTimeout + commonDuration, onLast);
    if (cleanupTimer != null) {
      unawaited(
        then<void>(
          (_) => cleanupTimer.cancel(),
          onError: (Object _, StackTrace _) {
            cleanupTimer.cancel();
          },
        ),
      );
    }
    return this.timeout(
      realTimeout,
      onTimeout: () async {
        if (onTimeout != null) {
          return onTimeout();
        } else {
          throw TimeoutException('${tag ?? runtimeType} timeout');
        }
      },
    );
  }
}

/// Разрешается один раз, затем отдаёт значение, а не будущее, которое его
/// разрешило: завершённое будущее всё ещё вызывает своих слушателей в зоне,
/// в которой было создано, что под тестом может быть фейк-async зоной, ничем
/// не приводимой в действие.
class ResolveOnce<T> {
  final Future<T> Function() _resolve;
  Future<T>? _pending;
  ({T value})? _resolved;

  ResolveOnce(this._resolve);

  Future<T> get value async {
    if (_resolved case (:final value)) return value;
    final value = await (_pending ??= _resolve());
    _resolved = (value: value);
    return value;
  }
}

extension CompleterExt<T> on Completer<T> {
  void safeCompleter(T value) {
    if (isCompleted) {
      return;
    }
    complete(value);
  }
}

/// Один запуск изолята за раз; [_onResult] получает только результат последнего ввода.
class LatestCompute<I, O> {
  final ComputeCallback<I, O> _task;
  final void Function(O result) _onResult;
  ({I input})? _pending;
  var _running = false;
  var _generation = 0;

  LatestCompute(this._task, this._onResult);

  void run(I input) {
    _generation++;
    _pending = (input: input);
    if (!_running) {
      unawaited(_drain());
    }
  }

  void cancel() {
    _generation++;
    _pending = null;
  }

  Future<void> _drain() async {
    _running = true;
    try {
      while (_pending != null) {
        final input = _pending!.input;
        _pending = null;
        final generation = _generation;
        try {
          final result = await compute(_task, input);
          if (generation == _generation) {
            _onResult(result);
          }
        } catch (e, s) {
          commonPrint.log(
            'Background compute failed: $e, $s',
            logLevel: LogLevel.warning,
          );
        }
      }
    } finally {
      _running = false;
    }
  }
}
