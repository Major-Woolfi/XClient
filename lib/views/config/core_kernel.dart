import 'package:xclient/common/common.dart';
import 'package:xclient/core/core.dart';
import 'package:xclient/providers/core_kernel.dart';
import 'package:xclient/ui/icons/icons.dart';
import 'package:xclient/ui/ui.dart';
import 'package:xclient/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CoreKernelView extends ConsumerWidget {
  const CoreKernelView({super.key});

  @override
  Widget build(BuildContext context, ref) {
    final appLocalizations = context.appLocalizations;
    final state = ref.watch(coreKernelProvider);

    return Scaffold(
      title: appLocalizations.coreKernel,
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(
          top: context.sectionsTopPadding,
          bottom: 16 + context.bottomInset,
        ),
        children: [
          _ActiveCoreCard(state: state),
          for (final type in CoreType.values)
            _CoreTypeSection(type: type, state: state),
        ],
      ),
    );
  }
}

class _ActiveCoreCard extends StatelessWidget {
  final CoreKernelState state;

  const _ActiveCoreCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final active = state.activeModel;

    return generateSection(
      title: appLocalizations.coreKernel,
      items: [
        ListItem(
          leading: _TypeBadge(type: active?.type),
          title: Text(active?.type.label ?? appLocalizations.coreUnknown),
          subtitle: Text(
            active == null
                ? appLocalizations.coreNotInstalledShort
                : '${appLocalizations.version}: ${active.spec.versionWithV}',
          ),
          trailing: const GlyphIcon(AppGlyphs.check),
        ),
      ],
    );
  }
}

class _CoreTypeSection extends ConsumerWidget {
  final CoreType type;
  final CoreKernelState state;

  const _CoreTypeSection({required this.type, required this.state});

  @override
  Widget build(BuildContext context, ref) {
    final appLocalizations = context.appLocalizations;
    final models = state.models[type] ?? const <CoreKernelModel>[];
    final isActive = state.activeType == type;

    return generateSection(
      title: type.label,
      items: [
        for (final model in models)
          _KernelVersionRow(
            model: model,
            active: isActive && model.spec.version == state.activeVersion,
            onInstall: () => ref
                .read(coreKernelProvider.notifier)
                .install(type, model.spec.version),
            onSwitch: () => ref
                .read(coreKernelProvider.notifier)
                .switchTo(type, model.spec.version),
            onUninstall: () => ref
                .read(coreKernelProvider.notifier)
                .uninstall(type, model.spec.version),
          ),
        if (models.isEmpty)
          ListItem(
            title: Text(appLocalizations.coreNoVersions),
            subtitle: Text(appLocalizations.coreNotInstalledShort),
          ),
      ],
    );
  }
}

class _KernelVersionRow extends StatelessWidget {
  final CoreKernelModel model;
  final bool active;
  final VoidCallback onInstall;
  final VoidCallback onSwitch;
  final VoidCallback onUninstall;

  const _KernelVersionRow({
    required this.model,
    required this.active,
    required this.onInstall,
    required this.onSwitch,
    required this.onUninstall,
  });

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    final status = switch (model.status) {
      CoreKernelStatus.installed => appLocalizations.coreInstalled,
      CoreKernelStatus.installing => appLocalizations.installing,
      CoreKernelStatus.error => appLocalizations.coreNotInstalledShort,
      CoreKernelStatus.idle => appLocalizations.coreNotInstalledShort,
    };

    return ListItem(
      title: Text(model.spec.versionWithV),
      subtitle: Text(status),
      trailing: _action(context),
    );
  }

  Widget _action(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    if (model.isInstalling) {
      return FilledButton(
        onPressed: null,
        child: Text(appLocalizations.installing),
      );
    }
    if (model.isInstalled) {
      if (active) {
        return FilledButton(
          onPressed: null,
          child: Text(appLocalizations.active),
        );
      }
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MinIconButtonTheme(
            child: IconButton(
              onPressed: onUninstall,
              tooltip: appLocalizations.remove,
              icon: const GlyphIcon(AppGlyphs.remove),
            ),
          ),
          FilledButton(onPressed: onSwitch, child: Text(appLocalizations.use)),
        ],
      );
    }
    return FilledButton(
      onPressed: onInstall,
      child: Text(
        model.hasError ? appLocalizations.retry : appLocalizations.install,
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  final CoreType? type;

  const _TypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final type = this.type;
    return Container(
      width: 40,
      height: 40,
      decoration: ShapeDecoration(
        shape: AppShape.circle,
        color: context.colorScheme.primaryContainer,
      ),
      child: Center(
        child: Text(
          type == null ? '?' : type.label.substring(0, 1),
          style: AppTextStyle.title3
              .of(context)
              .copyWith(color: context.colorScheme.onPrimaryContainer),
        ),
      ),
    );
  }
}
