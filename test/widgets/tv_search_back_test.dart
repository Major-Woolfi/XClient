import 'package:xclient/enum/enum.dart';
import 'package:xclient/manager/hotkey_manager.dart';
import 'package:xclient/models/models.dart';
import 'package:xclient/pages/home.dart';
import 'package:xclient/providers/providers.dart';
import 'package:xclient/state.dart';
import 'package:xclient/ui/icons/icons.dart';
import 'package:xclient/widgets/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/glyph_finders.dart';
import '../helpers/test_app.dart';

void main() {
  testWidgets('desktop escape runs the back flow and exits search', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final container = ProviderContainer();
    addTearDown(container.dispose);
    globalState.container = container;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: HostApp(
          builder: (context, child) => wrapAppScopes(context, child!),
          navigatorKey: globalState.navigatorKey,
          home: HotKeyManager(
            child: Scaffold(
              title: 'Logs',
              searchState: AppBarSearchState(onSearch: (_) {}),
              body: Center(
                child: TextButton(
                  onPressed: () {},
                  child: const Text('focus target'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byGlyph(AppGlyphs.search));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);

    // Сдвиньте фокус с текстового поля: собственные ярлыки EditableText проглатывают
    /// эскейп на некоторых платформах, поэтому привязка эскейпа применяется вне
    /// текстового ввода. (tap не фокусирует виджеты внутри области в тестах.)
    Focus.of(tester.element(find.text('focus target'))).requestFocus();
    await tester.pump();
    expect(
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<TextField>(),
      isNull,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(
      find.byType(TextField),
      findsNothing,
      reason: 'escape must exit search through the back flow',
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('TV back exits search on the desktop nested route', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var query = '';
    var closeCount = 0;
    final container = ProviderContainer(
      overrides: [
        navigationItemsStateProvider.overrideWithValue(
          NavigationItemsState(
            value: [
              NavigationItem(
                glyph: AppGlyphs.dashboard,
                label: PageLabel.dashboard,
                builder: (_) => Scaffold(
                  title: 'Search page',
                  searchState: AppBarSearchState(
                    onSearch: (value) {
                      query = value;
                    },
                  ),
                  body: const SizedBox(),
                ),
              ),
              NavigationItem(
                glyph: AppGlyphs.tools,
                label: PageLabel.tools,
                builder: (_) => const SizedBox.shrink(),
              ),
            ],
          ),
        ),
        systemActionProvider.overrideWith(
          () => _TestSystemAction(() => closeCount++),
        ),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    container.read(viewSizeProvider.notifier).value = const Size(1200, 800);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: HostApp(
          builder: (context, child) => wrapAppScopes(context, child!),
          home: const HomePage(),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(NavigationSidebar), findsOneWidget);

    await tester.tap(find.byGlyph(AppGlyphs.search));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'needle');
    expect(query, 'needle');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(closeCount, 0, reason: 'back must not fall through to app close');
    expect(find.byType(TextField), findsNothing);
    expect(query, isEmpty);
  });
}

class _TestSystemAction extends SystemAction {
  final int Function() closeCount;

  _TestSystemAction(this.closeCount);

  @override
  void build() {}

  @override
  Future<void> handleClose([bool exit = true]) async {
    closeCount();
  }
}
