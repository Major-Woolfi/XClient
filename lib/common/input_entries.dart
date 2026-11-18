import 'package:xclient/enum/enum.dart';

import 'string.dart';

enum InputIssueKind {
  keyTooLong,
  valueTooLong,
  missingValue,
  invalidUrl,
  invalidValue,
}

class InputIssue {
  final int line;
  final String raw;
  final InputIssueKind kind;

  const InputIssue({required this.line, required this.raw, required this.kind});

  @override
  bool operator ==(Object other) =>
      other is InputIssue &&
      other.line == line &&
      other.raw == raw &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(line, raw, kind);

  @override
  String toString() => 'InputIssue(line: $line, raw: $raw, kind: $kind)';
}

class ParsedInput<T> {
  final List<T> entries;
  final int skippedExisting;
  final List<InputIssue> issues;

  const ParsedInput({
    required this.entries,
    required this.skippedExisting,
    required this.issues,
  });

  bool get isValid => issues.isEmpty;
}

final _lineSeparator = RegExp(r'\r?\n');
final _listSeparator = RegExp(r'[,，]');
final _whitespace = RegExp(r'\s');
final _whitespaces = RegExp(r'\s+');
final _ruleTypes = {for (final action in RuleAction.values) action.value};

/// fake-ip-filter в режиме правил берёт целые правила вроде
/// `DOMAIN-SUFFIX,lan,real-ip`, поэтому их запятые nunca не делят строку.
bool _isRule(String value) {
  final comma = value.indexOf(',');
  return comma > 0 &&
      _ruleTypes.contains(value.substring(0, comma).trim().toUpperCase());
}

/// Строки, скопированные из последовательности YAML, сохраняют маркер `- ` и кавычки.
String _stripLineMarkup(String line) {
  var value = line.trim();
  if (value.startsWith('- ')) {
    value = value.substring(2).trim();
  }
  if (value.endsWith(',')) {
    value = value.substring(0, value.length - 1).trim();
  }
  return value;
}

String _unquote(String value) {
  if (value.length < 2) {
    return value;
  }
  final first = value[0];
  if ((first == '"' || first == "'") && value.endsWith(first)) {
    return value.substring(1, value.length - 1).trim();
  }
  return value;
}

/// Сохраняет каждую строку целой: запятые и кавычки правила перезаписи - его собственные.
ParsedInput<String> parseLineInput(
  String text, {
  Set<String> existing = const {},
}) {
  final entries = <String>[];
  final seen = <String>{};
  var skippedExisting = 0;
  for (final line in text.split(_lineSeparator)) {
    final value = line.trim();
    if (value.isEmpty || !seen.add(value)) {
      continue;
    }
    if (existing.contains(value)) {
      skippedExisting++;
      continue;
    }
    entries.add(value);
  }
  return ParsedInput(
    entries: entries,
    skippedExisting: skippedExisting,
    issues: const [],
  );
}

ParsedInput<String> parseListInput(
  String text, {
  Set<String> existing = const {},
  int? maxLength,
  bool Function(String value)? isValid,
}) {
  final entries = <String>[];
  final issues = <InputIssue>[];
  final seen = <String>{};
  var skippedExisting = 0;
  final lines = text.split(_lineSeparator);
  for (var index = 0; index < lines.length; index++) {
    final line = _stripLineMarkup(lines[index]);
    final whole = _unquote(line);
    final values = _isRule(whole) ? [whole] : line.split(_listSeparator);
    for (final raw in values) {
      final value = _unquote(raw.trim());
      if (value.isEmpty) {
        continue;
      }
      if (maxLength != null && value.length > maxLength) {
        issues.add(
          InputIssue(
            line: index + 1,
            raw: value,
            kind: InputIssueKind.valueTooLong,
          ),
        );
        continue;
      }
      if (isValid != null && !isValid(value)) {
        issues.add(
          InputIssue(
            line: index + 1,
            raw: value,
            kind: InputIssueKind.invalidValue,
          ),
        );
        continue;
      }
      if (!seen.add(value)) {
        continue;
      }
      if (existing.contains(value)) {
        skippedExisting++;
        continue;
      }
      entries.add(value);
    }
  }
  return ParsedInput(
    entries: entries,
    skippedExisting: skippedExisting,
    issues: issues,
  );
}

/// URL nunca не содержит пробелов, поэтому любая их последовательность разделяет два.
ParsedInput<String> parseUrlInput(
  String text, {
  required bool Function(String url) isValid,
  Set<String> existing = const {},
}) {
  final entries = <String>[];
  final issues = <InputIssue>[];
  final seen = <String>{};
  var skippedExisting = 0;
  final lines = text.split(_lineSeparator);
  for (var index = 0; index < lines.length; index++) {
    final line = _stripLineMarkup(lines[index]);
    for (final raw in line.isShareLink ? [line] : line.split(_whitespaces)) {
      final url = _unquote(raw);
      if (url.isEmpty) {
        continue;
      }
      if (!isValid(url)) {
        issues.add(
          InputIssue(
            line: index + 1,
            raw: url,
            kind: InputIssueKind.invalidUrl,
          ),
        );
        continue;
      }
      if (!seen.add(url)) {
        continue;
      }
      if (existing.contains(url)) {
        skippedExisting++;
        continue;
      }
      entries.add(url);
    }
  }
  return ParsedInput(
    entries: entries,
    skippedExisting: skippedExisting,
    issues: issues,
  );
}

/// Ключи nunca не содержат пробелов, а значения могут содержать `:` (`geosite:cn`,
/// `tls://1.1.1.1:853`, IPv6), поэтому первая последовательность пробелов делит строку,
/// а голый `:` nunca не делает этого. Ключ может заканчиваться на `:` или `=`, а значение
/// может начинаться с `=`, поэтому строки YAML и `key=value` парсятся без очистки.
MapEntry<String, String>? _splitMapLine(String line) {
  final whitespaceIndex = line.indexOf(_whitespace);
  String key;
  String value;
  if (whitespaceIndex == -1) {
    final equalsIndex = line.indexOf('=');
    if (equalsIndex == -1) {
      return null;
    }
    key = line.substring(0, equalsIndex);
    value = line.substring(equalsIndex + 1);
  } else {
    key = line.substring(0, whitespaceIndex);
    value = line.substring(whitespaceIndex).trim();
    if (value.startsWith('=')) {
      value = value.substring(1).trim();
    } else if (value.startsWith(':') && value.length > 1 && value[1] == ' ') {
      value = value.substring(1).trim();
    }
  }
  if (key.endsWith(':') || key.endsWith('=')) {
    key = key.substring(0, key.length - 1);
  }
  key = _unquote(key.trim());
  value = _unquote(value);
  if (key.isEmpty || value.isEmpty) {
    return null;
  }
  return MapEntry(key, value);
}

ParsedInput<MapEntry<String, String>> parseMapInput(
  String text, {
  Set<String> existingKeys = const {},
  int? keyMaxLength,
  int? valueMaxLength,
  bool ignoreKeyCase = false,
}) {
  String foldKey(String key) => ignoreKeyCase ? key.toLowerCase() : key;
  final takenKeys = existingKeys.map(foldKey).toSet();
  final entries = <MapEntry<String, String>>[];
  final issues = <InputIssue>[];
  final seen = <String>{};
  var skippedExisting = 0;
  final lines = text.split(_lineSeparator);
  for (var index = 0; index < lines.length; index++) {
    final line = _stripLineMarkup(lines[index]);
    if (line.isEmpty) {
      continue;
    }
    final entry = _splitMapLine(line);
    if (entry == null) {
      issues.add(
        InputIssue(
          line: index + 1,
          raw: line,
          kind: InputIssueKind.missingValue,
        ),
      );
      continue;
    }
    if (keyMaxLength != null && entry.key.length > keyMaxLength) {
      issues.add(
        InputIssue(
          line: index + 1,
          raw: entry.key,
          kind: InputIssueKind.keyTooLong,
        ),
      );
      continue;
    }
    if (valueMaxLength != null && entry.value.length > valueMaxLength) {
      issues.add(
        InputIssue(
          line: index + 1,
          raw: entry.value,
          kind: InputIssueKind.valueTooLong,
        ),
      );
      continue;
    }
    final key = foldKey(entry.key);
    if (!seen.add(key)) {
      continue;
    }
    if (takenKeys.contains(key)) {
      skippedExisting++;
      continue;
    }
    entries.add(entry);
  }
  return ParsedInput(
    entries: entries,
    skippedExisting: skippedExisting,
    issues: issues,
  );
}
