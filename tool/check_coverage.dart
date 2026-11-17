import 'dart:io';

const _defaultReport = 'coverage/lcov.info';

const _excludedPatterns = [
  '/generated/',
  'lib/l10n/',
  '.g.dart',
  '.freezed.dart',
];

// Каждой измеряемой группе нужен порог. Группа, которая отвечает только общему
// полу, может гнить бесплатно, потому что большая хорошо покрытая группа
// оплачивает это: так `pages`, `plugins` и `lib` достигли 20-50%, пока общий
// оставался зелёным. Добавление каталога верхнего уровня под `lib/` значит
// добавить его полор здесь, и `main()` прогонит прогоны, пока не сделаете.
//
// Положения только затягиваются вверх. Поднимайте одно, когда новые тесты
// поднимают группу; никогда не снижайте, чтобы прогон прошёл.
const _groupFloors = <String, double>{
  'core': 76.0,
  'database': 81.0,
  'ui': 97.0,
  'widgets': 82.0,
  'features': 81.0,
  'models': 67.0,
  'providers': 73.0,
  'common': 74.0,
  'manager': 68.0,
  'views': 66.0,
  'enum': 86.0,
  'pages': 71.0,
  'plugins': 67.0,
  'lib': 20.0,
};

class _Coverage {
  int found = 0;
  int hit = 0;

  double get percent => found == 0 ? 0 : hit / found * 100;
}

bool _isExcluded(String path) {
  final normalized = path.replaceAll(r'\', '/');
  return _excludedPatterns.any(normalized.contains);
}

String _group(String path) {
  final normalized = path.replaceAll(r'\', '/');
  // Якорь на собственном `lib/` проекта, который последний в пути. Первое
  // совпадение не оно, когда отчёт несёт абсолютные пути и нечто выше
  //チェкаута называется `lib` - клон в `~/dev/lib/`, запись кэша pub - и каждый
  // файл тогда попадает в каталог, который поведовал за тем.
  final int start;
  if (normalized.startsWith('lib/')) {
    start = 4;
  } else {
    final index = normalized.lastIndexOf('/lib/');
    if (index == -1) {
      return 'other';
    }
    start = index + 5;
  }
  final relative = normalized.substring(start);
  final separator = relative.indexOf('/');
  return separator == -1 ? 'lib' : relative.substring(0, separator);
}

void main(List<String> arguments) {
  final reportPath = arguments.isNotEmpty ? arguments.first : _defaultReport;
  var minimum = 0.0;
  if (arguments.length > 1) {
    // Опечатка иначе вылезла бы как необработанное FormatException и стек-трейс
    // Dart, что читается как сломанный инструмент, а не неверный аргумент.
    final parsed = double.tryParse(arguments[1]);
    if (parsed == null) {
      stderr.writeln(
        'The total floor must be a number, got "${arguments[1]}".\n'
        'Usage: dart run tool/check_coverage.dart [report] [total-floor]',
      );
      exit(64);
    }
    minimum = parsed;
  }

  final report = File(reportPath);
  if (!report.existsSync()) {
    stderr.writeln('Coverage report not found: $reportPath');
    exit(1);
  }

  final total = _Coverage();
  final byGroup = <String, _Coverage>{};
  var source = '';
  var excluded = false;

  for (final line in report.readAsLinesSync()) {
    if (line.startsWith('SF:')) {
      source = line.substring(3);
      excluded = _isExcluded(source);
      continue;
    }
    if (excluded || source.isEmpty) {
      continue;
    }
    final group = byGroup.putIfAbsent(_group(source), _Coverage.new);
    if (line.startsWith('LF:')) {
      final found = int.parse(line.substring(3));
      total.found += found;
      group.found += found;
    } else if (line.startsWith('LH:')) {
      final hit = int.parse(line.substring(3));
      total.hit += hit;
      group.hit += hit;
    }
  }

  if (total.found == 0) {
    stderr.writeln('No measurable lines in $reportPath after exclusions.');
    exit(1);
  }

  final groups = byGroup.entries.toList()
    ..sort((a, b) => b.value.found.compareTo(a.value.found));
  final failures = <String>[];
  for (final entry in groups) {
    final coverage = entry.value;
    final floor = _groupFloors[entry.key];
    final below = floor != null && coverage.percent < floor;
    if (below) {
      failures.add(
        '${entry.key} ${coverage.percent.toStringAsFixed(2)}% is below its '
        '${floor.toStringAsFixed(2)}% floor.',
      );
    }
    stdout.writeln(
      '${entry.key.padRight(12)} '
      '${coverage.hit.toString().padLeft(6)}/${coverage.found.toString().padLeft(6)} '
      '${coverage.percent.toStringAsFixed(1).padLeft(6)}%'
      '${floor == null ? ' (NO FLOOR)' : ' (floor ${floor.toStringAsFixed(0)}%)'}'
      '${below ? ' FAIL' : ''}',
    );
  }
  stdout.writeln(
    'TOTAL (generated code excluded): '
    '${total.hit}/${total.found} ${total.percent.toStringAsFixed(2)}%',
  );

  final missing = _groupFloors.keys
      .where((group) => !byGroup.containsKey(group))
      .toList();
  for (final group in missing) {
    failures.add('$group has a floor but no measured lines in the report.');
  }

  final unguarded = groups
      .map((entry) => entry.key)
      .where((group) => !_groupFloors.containsKey(group))
      .toList();
  for (final group in unguarded) {
    failures.add(
      '$group is measured but has no floor in _groupFloors; add one at or '
      'below its current coverage.',
    );
  }

  if (total.percent < minimum) {
    failures.add(
      'TOTAL ${total.percent.toStringAsFixed(2)}% is below the '
      '${minimum.toStringAsFixed(2)}% floor.',
    );
  }

  if (failures.isEmpty) {
    return;
  }
  for (final failure in failures) {
    stderr.writeln(failure);
  }
  exit(1);
}
