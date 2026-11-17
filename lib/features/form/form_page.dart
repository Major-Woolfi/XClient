import 'package:xclient/common/common.dart';
import 'package:xclient/ui/icons/icons.dart';
import 'package:xclient/ui/ui.dart';
import 'package:flutter/widgets.dart';

import 'custom_issue.dart';

/// Форма, которую открывает [showFormSheet]: сгруппированные строки под баром, чья галочка сохраняет,
/// с причиной, по которой последнее сохранение было отказано, над ними.
class FormPage extends StatelessWidget {
  final String title;
  final VoidCallback onSave;
  final String? saveLabel;
  final List<IconButtonData> actions;
  final String? error;
  final bool saving;
  final List<Widget> children;

  const FormPage({
    super.key,
    required this.title,
    required this.onSave,
    this.saveLabel,
    this.actions = const [],
    this.error,
    this.saving = false,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      title: title,
      iconActions: actions,
      confirmationAction: IconButtonData(
        glyph: AppGlyphs.check,
        tooltip: saveLabel ?? context.appLocalizations.save,
        isLoading: saving,
        onPressed: saving ? null : onSave,
      ),
      body: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(
          top: context.sectionsTopPadding,
          bottom: 20 + context.bottomInset,
        ),
        children: [
          ErrorBanner(message: error),
          ...children,
        ],
      ),
    );
  }
}
