import 'package:xclient/common/common.dart';
import 'package:xclient/widgets/widgets.dart';
import 'package:flutter/widgets.dart';

/// Режим пакета формы: одно поле из строк и сколько из них оно добавляет.
class BatchSection<T> extends StatelessWidget {
  final BatchInput<T> batch;
  final TextEditingController controller;
  final ParsedInput<T>? parsed;
  final ValueChanged<String> onChanged;

  const BatchSection({
    super.key,
    required this.batch,
    required this.controller,
    required this.parsed,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final parsed = this.parsed;
    return generateSection(
      footer: parsed == null || controller.text.trim().isEmpty
          ? null
          : context.appLocalizations.batchPreviewTip(
              parsed.entries.length,
              parsed.skippedExisting,
            ),
      items: [
        DecorationListItem(
          title: TextField(
            controller: controller,
            autofocus: true,
            minLines: 4,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            autocorrect: false,
            onChanged: onChanged,
            decoration: InputDecoration.collapsed(
              border: const NoInputBorder(),
              hintText: batch.formatTip,
            ),
          ),
        ),
      ],
    );
  }
}


