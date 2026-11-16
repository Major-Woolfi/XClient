import 'package:xclient/common/common.dart';
import 'package:xclient/core/core.dart';
import 'package:xclient/providers/core_kernel.dart';
import 'package:xclient/ui/icons/icons.dart';
import 'package:xclient/ui/ui.dart';
import 'package:xclient/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Экран управления ядрами (Clash.Meta / Xray-core).
class CoreKernelView extends ConsumerWidget {
  const CoreKernelView({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final appLocalizations = context.appLocalizations;
    final state = ref.watch(coreKernelProvider).state;

    return Scaffold(
      title: appLocalizations.coreKernel,
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(
          top: context.contentTopPadding,
          bottom: 32 + context.bottomInset,
        ),
        children: [
          _ActiveCoreCard(state: state),
          const SizedBox(height: 16),
          for (final type in CoreType.values) ...[
            _CoreTypeSection(type: type, state: state),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

/// Карточка активного ядра.
class _ActiveCoreCard extends ConsumerWidget {
  const _ActiveCoreCard({required this.state});

  final CoreKernelState state;

  @override
  Widget build(BuildContext context, ref) {
    final appLocalizations = context.appLocalizations;
    final active = state.getActiveModel();

    return _SectionCard(
      title: appLocalizations.coreKernel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: context.colorScheme.primaryContainer,
                  ),
                  child: Center(
                    child: Text(
                      active?.type.label[0] ?? '?',
                      style: AppTextStyle.title3.of(context).copyWith(
                        color: context.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        active?.type.label ?? appLocalizations.coreUnknown,
                        style: AppTextStyle.title3.of(context),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        active != null
                            ? '${appLocalizations.version}: ${active.spec.versionWithV}'
                            : appLocalizations.coreNotInstalledShort,
                        style: AppTextStyle.body.of(context).copyWith(
                          color: context.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const GlyphIcon(AppGlyphs.openExternal),
              ],
            ),
          ),
          if (active != null) ...[
            const SizedBox(height: 8),
            Text(
              '${appLocalizations.version}: ${active.spec.versionWithV}',
              style: AppTextStyle.body.of(context),
            ),
          ],
        ],
      ),
    );
  }
}

/// Sekция одного типа ядра.
class _CoreTypeSection extends ConsumerWidget {
  const _CoreTypeSection({
    required this.type,
    required this.state,
  });

  final CoreType type;
  final CoreKernelState state;

  @override
  Widget build(BuildContext context, ref) {
    final appLocalizations = context.appLocalizations;
    final models = state.models[type] ?? const [];
    final isActive = state.activeType == type;

    return _SectionCard(
      title: type.label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    appLocalizations.coreVersions,
                    style: AppTextStyle.title3.of(context),
                  ),
                ),
                GlyphIcon(
                  AppGlyphs.check,
                  color: isActive ? context.colorScheme.primary : null,
                ),
                const GlyphIcon(AppGlyphs.more),
              ],
            ),
          ),
          const SizedBox(height: 8),
          ...models.map(
            (model) => _KernelVersionRow(
              model: model,
              type: type,
              isActive: isActive && model.spec.version == state.activeVersion,
              onInstall: (spec) async {
                await ref.read(coreKernelProvider).install(type, spec.version);
              },
              onSwitch: (spec) async {
                await ref.read(coreKernelProvider).switchTo(type, spec.version);
              },
              onUninstall: (spec) async {
                await ref.read(coreKernelProvider).uninstall(type, spec.version);
              },
            ),
          ),
          if (models.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  appLocalizations.coreNoVersions,
                  style: AppTextStyle.body.of(context).copyWith(
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Строка версии ядра.
class _KernelVersionRow extends ConsumerWidget {
  const _KernelVersionRow({
    required this.model,
    required this.type,
    required this.isActive,
    required this.onInstall,
    required this.onSwitch,
    required this.onUninstall,
  });

  final CoreKernelModel model;
  final CoreType type;
  final bool isActive;
  final Future<void> Function(CoreSpec spec) onInstall;
  final Future<void> Function(CoreSpec spec) onSwitch;
  final Future<void> Function(CoreSpec spec) onUninstall;

  @override
  Widget build(BuildContext context, ref) {
    final appLocalizations = context.appLocalizations;
    final isInstalled = model.isInstalled;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  model.spec.versionWithV,
                  style: AppTextStyle.body.of(context),
                ),
                const SizedBox(height: 2),
                Text(
                  isInstalled
                      ? appLocalizations.coreInstalled
                      : appLocalizations.coreNotInstalledShort,
                  style: AppTextStyle.body.of(context).copyWith(
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          _buildActionButton(context, ref),
        ],
      ),
    );
  }

  Widget _buildActionButton(BuildContext context, WidgetRef ref) {
    final appLocalizations = context.appLocalizations;

    if (model.isInstalled) {
      if (isActive) {
        return FilledButton(
          onPressed: null,
          child: Text(appLocalizations.active),
        );
      }
      return FilledButton(
        onPressed: () => onSwitch(model.spec),
        child: Text(appLocalizations.use),
      );
    }

    return FilledButton(
      onPressed: () => onInstall(model.spec),
      child: Text(appLocalizations.install),
    );
  }
}

/// Карточка секции с заголовком.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: context.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              title,
              style: AppTextStyle.title3.of(context).copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Divider(height: 1),
          child,
        ],
      ),
    );
  }
}
