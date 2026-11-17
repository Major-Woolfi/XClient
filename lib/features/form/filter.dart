import 'package:xclient/models/models.dart';
import 'package:xclient/providers/providers.dart';
import 'package:xclient/ui/ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Что regexp2 mihomo, спрошенного через ядро, отвергает в каждом фильтре, по
/// индексу, или null, когда ядро нельзя спросить.
Future<Map<int, String>?> checkFilters(
  WidgetRef ref,
  List<String> filters,
) async {
  if (filters.every((filter) => filter.isEmpty)) {
    return const {};
  }
  try {
    return await ref.read(coreHandlerProvider).validateFilters(filters);
  } catch (_) {
    return null;
  }
}

// mihomo разделяет `filter` и `exclude-filter` на обратные кавычки и сопоставляет каждую
// часть как свое eigenes regex, поэтому фильтр применяется добавлением его частей.
const _filterSeparator = '`';

List<String> filterParts(String? value) => [
  for (final part in (value ?? '').split(_filterSeparator))
    if (part.isNotEmpty) part,
];

String? joinFilterParts(List<String> parts) =>
    parts.isEmpty ? null : parts.join(_filterSeparator);

extension FilterExt on Filter {
  bool isAppliedTo(String? value) {
    final parts = filterParts(value);
    final own = filterParts(regex);
    return own.isNotEmpty && own.every(parts.contains);
  }
}

class FilterRegexText extends StatelessWidget {
  final String regex;

  const FilterRegexText(this.regex, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      regex,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTextStyle.footnote
          .of(context)
          .toJetBrainsMono
          .copyWith(color: context.colorScheme.tertiary),
    );
  }
}
