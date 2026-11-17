import 'package:xclient/common/common.dart';
import 'package:xclient/providers/action.dart';
import 'package:xclient/providers/app.dart';
import 'package:xclient/providers/config.dart';
import 'package:xclient/state.dart';
import 'package:xclient/ui/ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/state.dart';

/// Пересобранный ThemeData никогда не равен последнему, и ThemeCrossFade затухает на этом.
final _appThemes = <Brightness, ({Object inputs, ThemeData theme})>{};

ThemeData watchAppTheme(WidgetRef ref, Brightness brightness) {
  final locale = ref.watch(appSettingProvider.select((state) => state.locale));
  final fontFamily = ref.watch(
    themeSettingProvider.select((state) => state.fontFamily),
  );
  final colorScheme = ref.watch(genColorSchemeProvider(brightness));
  final locales = [
    ?getLocaleForString(locale),
    ...WidgetsBinding.instance.platformDispatcher.locales,
  ];
  final inputs = (
    platform: defaultTargetPlatform,
    fontFamily: fontFamily,
    colorScheme: colorScheme,
    locales: locales.join(','),
  );
  if (_appThemes[brightness] case (
    inputs: final cached,
    :final theme,
  ) when cached == inputs) {
    return theme;
  }
  final theme = ThemeData(
    colorScheme: colorScheme,
    fontFamily: fontFamily,
    fontFamilyFallback: appFontFamilyFallback(
      platform: defaultTargetPlatform,
      locales: locales,
      fontFamily: fontFamily,
    ),
    elevatedColorScheme: brightness == Brightness.dark
        ? colorScheme.elevated
        : null,
  );
  _appThemes[brightness] = (inputs: inputs, theme: theme);
  return theme;
}

class ThemeManager extends ConsumerWidget {
  final Widget child;

  const ThemeManager({super.key, required this.child});

  Widget _buildSystemUi(Widget child) {
    if (!system.isAndroid) {
      return child;
    }
    return Consumer(
      builder: (context, ref, _) {
        final brightness = ref.watch(currentBrightnessProvider);
        final iconBrightness = brightness == Brightness.light
            ? Brightness.dark
            : Brightness.light;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: iconBrightness,
            systemNavigationBarIconBrightness: iconBrightness,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarDividerColor: Colors.transparent,
            // Страницы скроллятся под навигационной панелью. Android затемняет только
            // трехкнопочную панель для неё; жестовая ручка остается свободной.
            systemNavigationBarContrastEnforced: true,
          ),
          sized: false,
          child: child,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, ref) {
    globalState.measure = MeasureScope.of(context);
    return AppViewScope(
      child: _AppMediaQuery(
        // Каждая перестройка вне ближайшего LayoutBuilder, переход роута на каждом
        // своем кадре, перекладывает это наружу; границы предотвращают перерисовку приложения от корня.
        child: RepaintBoundary(
          child: LayoutBuilder(
            builder: (_, constraints) {
              ref
                  .read(themeActionProvider.notifier)
                  .updateViewSize(
                    Size(constraints.maxWidth, constraints.maxHeight),
                  );
              return RepaintBoundary(child: _buildSystemUi(child));
            },
          ),
        ),
      ),
    );
  }
}

class AppViewScope extends ConsumerWidget {
  const AppViewScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMobile = ref.watch(isMobileViewProvider);
    return ViewScope(
      size: ref.watch(viewSizeProvider),
      isMobile: isMobile,
      windowControls: windowControlsOverPage(
        isMacOS: system.isMacOS,
        version: ref.watch(versionProvider),
        isMobileView: isMobile,
      ),
      child: child,
    );
  }
}

class _AppMediaQuery extends StatelessWidget {
  const _AppMediaQuery({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final data = MediaQuery.of(context);
    final padding = data.padding;
    return MediaQuery(
      data: data.copyWith(
        padding: padding.copyWith(
          top: padding.top > data.size.height * 0.3 ? 20.0 : padding.top,
        ),
      ),
      child: child,
    );
  }
}


