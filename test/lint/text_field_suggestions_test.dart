import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'sources.dart';

final _passwordInputType = RegExp(
  r'\benableSuggestions:\s*false\b|\bTextInputType\.visiblePassword\b',
);

const _secretFields = {'lib/features/form/form_row.dart'};

void main() {
  test('only secret fields ask Android for a password keyboard', () {
    final offenders = <String>[];

    for (final entity in sourceEntities()) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final path = portablePath(p.relative(entity.path));
      if (path.contains('/generated/') || _secretFields.contains(path)) {
        continue;
      }
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final match = _passwordInputType.firstMatch(lines[i]);
        if (match != null) {
          offenders.add(
            '$path:${i + 1} - ${match[0]} makes Android input '
            'methods treat the field as a password, with no clipboard or '
            'Chinese input; keep autocorrect: false alone.',
          );
        }
      }
    }

    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
