import 'package:xclient/core/controller.dart';
import 'package:xclient/core/interface.dart';
import 'package:xclient/enum/enum.dart';
import 'package:xclient/features/connection/tracker_info_list.dart';
import 'package:xclient/models/models.dart';
import 'package:xclient/providers/providers.dart';
import 'package:xclient/state.dart';
import 'package:xclient/views/connection/requests.dart';
import 'package:xclient/views/dashboard/widgets/connection_stats.dart';
import 'package:xclient/views/dns_queries.dart';
import 'package:xclient/widgets/widgets.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/test_app.dart';
import '../../helpers/test_profiles.dart';
import '../../helpers/host_scaffold.dart';

class _MockCore extends Mock implements CoreHandlerInterface {}

const _mobileSize = Size(400, 800);

TrackerInfo _request(int index) {
  return TrackerInfo(
    id: '$index',
    start: DateTime.utc(2026),
    metadata: Metadata(
      network: 'tcp',
      host: 'host-$index.test',
      destinationIP: '1.1.1.1',
      destinationPort: '443',
      process: 'curl',
    ),
    chains: const ['Proxy'],
    rule: 'DOMAIN',
    rulePayload: 'host-$index.test',
  );
}

Finder _stat(String label) => find.descendant(
  of: find.byType(ConnectionStatsCard),
  matching: find.text(label),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockCore core;
  late ProviderContainer container;

  setUp(() {
    core = _MockCore();
    when(() => core.getConnectionCount()).thenAnswer((_) async => 0);
    container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(TestProfiles.new),
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
        coreStatusProvider.overrideWithBuild((_, _) => CoreStatus.connected),
      ],
    );
    globalState.container = container;
  });

  tearDown(() => container.dispose());

  Future<void> pumpCard(
    WidgetTester tester, {
    Size size = _mobileSize,
    Locale? locale,
  }) async {
    container.read(viewSizeProvider.notifier).value = size;
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          locale: locale,
          child: HostScaffold(
            body: ListView(children: const [ConnectionStatsCard()]),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> teardownCard(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('counts what the Core is holding open', (tester) async {
    when(() => core.getConnectionCount()).thenAnswer((_) async => 34);

    await pumpCard(tester);

    expect(find.text('34'), findsOneWidget);

    await teardownCard(tester);
  });

  testWidgets('the request and DNS counts follow on the throttled cadence', (
    tester,
  ) async {
    await pumpCard(tester);

    container.read(requestCountProvider.notifier).value = 1284;
    container.read(dnsQueryCountProvider.notifier).value = 42;
    await tester.pump();

    expect(find.text('1,284'), findsNothing);
    await tester.pump(const Duration(milliseconds: 301));

    expect(find.text('1,284'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);

    await teardownCard(tester);
  });

  testWidgets('a count too long for a third of a phone is shortened in any '
      'locale', (tester) async {
    when(() => core.getConnectionCount()).thenAnswer((_) async => 99999);
    container.read(requestCountProvider.notifier).value = 123456;

    await pumpCard(tester, locale: const Locale('zh', 'CN'));

    expect(find.text('99,999'), findsOneWidget);
    expect(find.text('123K'), findsOneWidget);

    await teardownCard(tester);
  });

  testWidgets('every count opens its own list in a sheet', (tester) async {
    await pumpCard(tester);

    for (final (label, view) in [
      ('Live connections', RequestsView),
      ('Recent requests', RequestsView),
      ('DNS queries', DnsQueriesView),
    ]) {
      await tester.tap(_stat(label));
      await tester.pumpAndSettle();

      expect(find.byType(view), findsOneWidget);
      expect(
        tester.getTopLeft(find.byType(SheetDragHandle)).dy,
        closeTo(_mobileSize.height * (1 - snapSheetDetents.first), 1),
      );

      await tester.tapAt(const Offset(200, 20));
      await tester.pumpAndSettle();
      expect(find.byType(view), findsNothing);
    }

    await teardownCard(tester);
  });

  testWidgets('a sheet switching feeds opens each at its own start', (
    tester,
  ) async {
    when(() => core.getConnections()).thenAnswer(
      (_) async => [for (var i = 0; i < 100; i++) _request(1000 + i)],
    );
    final notifier = container.read(requestsProvider.notifier);
    for (var i = 0; i < 100; i++) {
      notifier.addRequest(_request(i));
    }
    await pumpCard(tester);
    await tester.tap(_stat('Recent requests'));
    await tester.pumpAndSettle();
    ScrollPosition position() => tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(RequestsView),
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is Scrollable &&
                      axisDirectionToAxis(widget.axisDirection) ==
                          Axis.vertical,
                ),
              )
              .first,
        )
        .position;
    expect(position().pixels, position().maxScrollExtent);

    await tester.tap(find.text('Recent requests').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Running'));
    await tester.pumpAndSettle();
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(position().pixels, 0);

    await tester.tap(find.text('Running').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recent requests').last);
    await tester.pumpAndSettle();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(position().pixels, position().maxScrollExtent);

    await teardownCard(tester);
  });

  testWidgets('the requests sheet keeps the newest request at its top while '
      'it is dragged and requests arrive', (tester) async {
    final notifier = container.read(requestsProvider.notifier);
    var next = 0;
    while (next < 200) {
      notifier.addRequest(_request(next++));
    }
    await pumpCard(tester);
    await tester.tap(_stat('Recent requests'));
    await tester.pumpAndSettle();
    final list = find.descendant(
      of: find.byType(TrackerInfoList),
      matching: find.byType(Scrollable),
    );
    ScrollPosition position() =>
        tester.state<ScrollableState>(list.first).position;

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(SheetDragHandle)),
    );
    for (var frame = 0; frame < 40; frame++) {
      if (frame % 10 == 0) {
        for (var i = 0; i < 5; i++) {
          notifier.addRequest(_request(next++));
        }
      }
      await gesture.moveBy(const Offset(0, -6));
      await tester.pump(const Duration(milliseconds: 16));
      expect(position().pixels, position().maxScrollExtent);
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(position().pixels, position().maxScrollExtent);
    expect(find.textContaining('host-${next - 1}.test'), findsWidgets);

    await teardownCard(tester);
  });
}


