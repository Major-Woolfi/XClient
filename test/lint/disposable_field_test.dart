import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'sources.dart';

const _disposableTypes = {
  'AnimationController',
  'FocusNode',
  'PageController',
  'ScrollController',
  'StreamController',
  'TabController',
  'TextEditingController',
  'ValueNotifier',
};

/// Поля, которые анализатор бы пометил, но умышленно никогда не освобождаются, ключевые по
/// `<path>#<field>`. Всё здесь должно пережить процесс, а не виджет.
const _allowed = {
  // `CoreEventManager` - синглтон с приватным конструктором, который распространяет
  /// ядерные события на всём протяжении прогона; закрытие его контроллера ukonчит доставку событий.
  'lib/core/event.dart#_controller',
  // `App` - Android-плагин на весь процесс; notifier retransлирует состояние
  /// клавиатуры с канала платформы на всём протяжении прогона.
  'lib/plugins/app.dart#floatingKeyboard',
};

final _declaration = RegExp(
  r'^\s+(?:late\s+)?final\s+(?:[A-Za-z][\w<>,\s?]*\s+)?(_?[A-Za-z]\w*)\s*=\s*'
  r'(?:[A-Za-z]\w*)?'
  '(${_disposableTypes.join('|')})'
  r'\b',
);

/// Поле `late`, объявленное без инициализатора, которое паттерн выше не может
/// увидеть, потому что на строке нет вызова конструктора. Они строятся в `initState`
/// и владеются так же - `pages/editor.dart` держал `late TextEditingController`
/// живым для процесса таким образом.
final _lateDeclaration = RegExp(
  '^\\s+late\\s+(?:final\\s+)?(${_disposableTypes.join('|')})'
  r'(?:<[\w<>,\s?]*>)?\??\s+(_?[A-Za-z]\w*)\s*;',
);

bool _isGenerated(String path) {
  return path.contains('/generated/') ||
      path.endsWith('.g.dart') ||
      path.endsWith('.freezed.dart');
}

void main() {
  test('every self-created disposable field is released in the same file', () {
    final offenders = <String>[];

    for (final entity in sourceEntities()) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final relative = p.relative(entity.path);
      if (_isGenerated(relative)) {
        continue;
      }
      final source = entity.readAsStringSync();
      final lines = source.split('\n');
      for (var i = 0; i < lines.length; i++) {
        final match = _declaration.firstMatch(lines[i]);
        final lateMatch = match == null
            ? _lateDeclaration.firstMatch(lines[i])
            : null;
        if (match == null && lateMatch == null) {
          continue;
        }
        final field = match?.group(1) ?? lateMatch!.group(2)!;
        final type = match?.group(2) ?? lateMatch!.group(1)!;
        if (_allowed.contains('$relative#$field')) {
          continue;
        }
        final released =
            source.contains('$field.dispose()') ||
            source.contains('$field.close()');
        if (!released) {
          offenders.add('$relative:${i + 1} $field ($type)');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'These fields are constructed by their owner but never disposed or '
          'closed. Release them in `dispose()`, or add the declaration to '
          '`_allowed` with the reason it outlives its owner.\n'
          '${offenders.join('\n')}',
    );
  });

  test('the allow list has no stale entries', () {
    for (final entry in _allowed) {
      final parts = entry.split('#');
      final file = File(parts.first);
      expect(
        file.existsSync(),
        isTrue,
        reason: '$entry names a file that no longer exists',
      );
      expect(
        file.readAsStringSync(),
        contains(parts.last),
        reason: '$entry names a field that no longer exists',
      );
    }
  });
}
