import 'dart:convert';

import 'models.dart';

const changelogTitle = '# Changelog';
/// Всё ниже этого маркера предшествует структурированному конвейеру и хранится
/// буквально. Генератор никогда не пишет за ним.
const changelogFrozenMarker = '<!-- changelog:frozen -->';

const changelogFrozenNote =
    '<!-- Entries below predate the structured pipeline. Their wording is kept as '
    'written; only the heading and list style were normalized. -->';

const releaseBeginMarker = '<!-- XClient:changelog:begin -->';
const releaseEndMarker = '<!-- XClient:changelog:end -->';
/// Открывает HTML-комментарий, несущий структурированные записи в приложение.
/// Диалог обновления читает их из релиза, который GitHub уже возвращает, поэтому
/// заметки не стоят своего собственного запроса и остаются невидимыми на странице релиза.
const releaseJsonBeginMarker = '<!-- XClient:changelog:json';
const releaseJsonEndMarker = '-->';

const telegramLimit = 900;

const emptyVersionNote = 'Internal improvements only.';

String renderMarkdown(Changelog changelog) {
  final buffer = StringBuffer()
    ..writeln(changelogTitle)
    ..writeln();
  for (final version in changelog.versions) {
    buffer
      ..writeln(_heading(version))
      ..writeln();
    if (version.isEmpty) {
      buffer
        ..writeln(emptyVersionNote)
        ..writeln();
    }
    for (final group in version.groups) {
      buffer
        ..writeln('**${group.type.title}**')
        ..writeln();
      for (final entry in group.entries) {
        buffer.writeln('- ${_prefix(entry)}${entry.text} (${entry.id})');
      }
      buffer.writeln();
    }
  }
  buffer
    ..writeln(changelogFrozenMarker)
    ..writeln(changelogFrozenNote)
    ..writeln();
  return buffer.toString();
}

String renderRelease(ChangelogVersion version) {
  final buffer = StringBuffer()..writeln(releaseBeginMarker);
  if (version.isEmpty) {
    buffer.writeln('- $emptyVersionNote');
  }
  for (final group in version.groups) {
    buffer.writeln('### ${group.type.title}');
    for (final entry in group.entries) {
      buffer.writeln('- ${_prefix(entry)}${entry.text}');
    }
    buffer.writeln();
  }
  buffer
    ..writeln(releaseEndMarker)
    ..writeln()
    ..write(renderReleaseJson(version));
  return buffer.toString();
}
/// та же версия как машиночитаемый JSON, обёрнутый в HTML-комментарий, чтобы он
/// путешествовал с телом релиза, не показываясь на странице релиза.
///
/// `>` экранируется, чтобы никакая запись не закрыла комментарий раньше
/// времени, что удерживает строку changelog, содержащая `-->`, от обрезания
/// полезной нагрузки.
String renderReleaseJson(ChangelogVersion version) {
  final payload = jsonEncode(
    Changelog(versions: <ChangelogVersion>[version]).toJson(),
  ).replaceAll('>', r'\u003e');
  return '$releaseJsonBeginMarker\n$payload\n$releaseJsonEndMarker\n';
}
/// Подпись отправляется с режимом разбора, поэтому текст записи — это разметка,
/// не текст: тема коммита, несущая `<`, — некорректный тег, и Telegram отклоняет
/// всю загрузку. HTML, а не Markdown, потому что это единственный режим разбора
/// Telegram с определённым экранированием - унаследованный Markdown не имеет
/// ни одного, а тема, содержащая одиночный `*` или `_`, не может быть сделана
/// безопасной в нём.
String escapeTelegramHtml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
/// Подписи Telegram ограничены 1024 символами, поэтому текст обрезается с
/// ссылкой на полные заметки вместо того, чтобы провалить загрузку.
String renderTelegram(ChangelogVersion version, {String? moreUrl}) {
  final buffer = StringBuffer();
  if (version.isEmpty) {
    buffer.writeln('• ${escapeTelegramHtml(emptyVersionNote)}');
  }
  for (final group in version.groups) {
    buffer.writeln('<b>${escapeTelegramHtml(group.type.title)}</b>');
    for (final entry in group.entries) {
      buffer.writeln('• ${escapeTelegramHtml(entry.text)}');
    }
    buffer.writeln();
  }
  final text = buffer.toString().trimRight();
  if (_telegramVisibleLength(text) <= telegramLimit) {
    return text;
  }
  final kept = StringBuffer();
  var length = 0;
  for (final line in text.split('\n')) {
    length += _telegramVisibleLength(line) + 1;
    if (length > telegramLimit) {
      break;
    }
    kept.writeln(line);
  }
  final more = moreUrl == null ? '' : '\n$moreUrl';
  return '${kept.toString().trimRight()}\n\n…$more';
}

int _telegramVisibleLength(String markup) => markup
    .replaceAll(RegExp('<[^>]*>'), '')
    .replaceAll(RegExp('&[a-z]+;'), '&')
    .length;
/// Заголовки версий остаются единственным уровнем `##`; группы — жирные строки,
/// потому что релиз несет горсть записей, а `###` на группу перевешивает их.
String _heading(ChangelogVersion version) => version.date.isEmpty
    ? '## ${version.tag}'
    : '## ${version.tag} (${version.date})';

String _prefix(ChangelogEntry entry) =>
    entry.scope == null ? '' : '**${entry.scope}** ';

