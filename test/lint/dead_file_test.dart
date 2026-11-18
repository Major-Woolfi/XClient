import 'dart:io';

import 'package:test/test.dart';

const _entryPoints = ['lib/main.dart'];

/// Типы, и верхние имена, которые файл публикует рядом с ними - паттерн
/// синглтона `final appPath = AppPath()` так большая часть `lib/common`
/// на самом деле потребляется.
final _declaration = RegExp(
  r'^(?:abstract |sealed |final |base |mixin )*'
  r'(?:(?:class|enum|mixin)\s+([A-Za-z]\w*)'
  r'|(?:final|const)\s+(?:[\w<>,\s\[\]?]+\s+)?([a-z]\w*)\s*=)',
  multiLine: true,
);

Iterable<File> _dartFiles({required bool includeGenerated}) sync* {
  for (final root in ['lib', 'test', 'tool', 'plugins']) {
    final directory = Directory(root);
    if (!directory.existsSync()) {
      fail('$root no longer exists; update this test.');
    }
    for (final entity in directory.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final generated =
          entity.path.endsWith('.g.dart') ||
          entity.path.endsWith('.freezed.dart') ||
          entity.path.contains('/generated/');
      if (generated && !includeGenerated) continue;
      yield entity;
    }
  }
}

bool _isBarrel(String source) {
  final lines = source
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !line.startsWith('//'));
  return lines.isNotEmpty &&
      lines.every(
        (line) => line.startsWith('export ') || line.startsWith('import '),
      );
}

void main() {
  test('every file under lib declares something used outside itself', () {
    // Сгенерированный код считается потребителем, но никогда декларатором: notifier
    /// riverpod alcanцируется через провайдер, который порождает его аннотация.
    final consumers = {
      for (final file in _dartFiles(includeGenerated: true))
        file.path: file.readAsStringSync(),
    };
    final sources = {
      for (final file in _dartFiles(includeGenerated: false))
        file.path: consumers[file.path]!,
    };
    final barrels = {
      for (final MapEntry(key: path, value: source) in sources.entries)
        if (_isBarrel(source)) path,
    };

    final orphans = <String>[];

    for (final MapEntry(key: path, value: source) in sources.entries) {
      if (!path.startsWith('lib/')) {
        continue;
      }
      if (barrels.contains(path) || _entryPoints.contains(path)) continue;
      if (path.startsWith('lib/l10n/')) continue;

      // Расширения и typedef alcanцируются через типы, к которым они привязаны,
      /// никогда не по имени, так что файл, публикующий только их, не может быть
      /// измерен таким образом.
      final names = _declaration
          .allMatches(source)
          .map((match) => match.group(1) ?? match.group(2)!)
          .toSet();
      if (names.isEmpty) continue;

      final used = consumers.entries.any((entry) {
        if (entry.key == path || barrels.contains(entry.key)) return false;
        return names.any((name) => RegExp('\\b$name\\b').hasMatch(entry.value));
      });

      if (!used) {
        orphans.add(
          '$path - publishes ${names.join(', ')}, none of which is referenced '
          'anywhere else. A barrel export keeps it compiling; it is still dead.',
        );
      }
    }

    expect(orphans, isEmpty, reason: orphans.join('\n'));
  });
}
