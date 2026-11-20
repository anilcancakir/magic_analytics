import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_analytics/magic_analytics.dart';

import '../helpers/test_helpers.dart';

Route<void> _route(String? name) => PageRouteBuilder<void>(
  settings: RouteSettings(name: name),
  pageBuilder: (context, animation, secondaryAnimation) => const SizedBox(),
);

void main() {
  late FakeAnalytics fake;

  setUp(() {
    resetMagic();
    fake = Analytics.fake();
  });

  tearDown(() {
    Analytics.unfake();
    MagicRouter.reset();
  });

  group('page_view on navigation', () {
    test('a push reports the page name as name and location', () async {
      AnalyticsNavigatorObserver().didPush(_route('/monitors/:id'), null);
      await drainAnalytics();

      final RecordedAnalyticsCall screen = fake.screens.single;

      expect(screen.name, '/monitors/:id');
      expect(screen.parameters['location'], '/monitors/:id');
      expect(screen.parameters['referrer'], isNull);
    });

    test('the previous page becomes the referrer', () async {
      final AnalyticsNavigatorObserver observer = AnalyticsNavigatorObserver();

      observer.didPush(_route('/'), null);
      observer.didPush(_route('/monitors/:id'), null);
      await drainAnalytics();

      expect(fake.screens.last.parameters['referrer'], '/');
    });

    test('a replace reports the new page', () async {
      AnalyticsNavigatorObserver().didReplace(
        newRoute: _route('/settings'),
        oldRoute: _route('/'),
      );
      await drainAnalytics();

      expect(fake.screens.single.name, '/settings');
    });

    test('a page with no name is skipped', () async {
      AnalyticsNavigatorObserver().didPush(_route(null), null);
      await drainAnalytics();

      expect(fake.screens, isEmpty);
    });

    test('popping a page reports the page it reveals', () async {
      AnalyticsNavigatorObserver().didPop(
        _route('/monitors/:id'),
        _route('/monitors'),
      );
      await drainAnalytics();

      expect(fake.screens.single.name, '/monitors');
    });

    test('popping a nameless dialog does not report the page again', () async {
      AnalyticsNavigatorObserver().didPop(_route(null), _route('/monitors'));
      await drainAnalytics();

      expect(fake.screens, isEmpty);
    });

    test('a page named by .name() reports its route pattern', () async {
      MagicRoute.page(
        '/monitors/:id',
        () => const SizedBox(),
      ).name('monitors.show');

      AnalyticsNavigatorObserver().didPush(_route('monitors.show'), null);
      await drainAnalytics();

      expect(fake.screens.single.name, 'monitors.show');
      expect(fake.screens.single.parameters['location'], '/monitors/:id');
    });
  });

  testWidgets('through the router, the pattern is reported, never the id', (
    tester,
  ) async {
    // Faked again inside the body: the manager's send queue has to be created
    // in the widget test's fake-async zone for pumps to drain it.
    fake = Analytics.fake();
    MagicRoute.page('/', () => const SizedBox());
    MagicRoute.page('/monitors/:id', () => const SizedBox());
    MagicRouter.instance.addObserver(AnalyticsNavigatorObserver());

    await tester.pumpWidget(
      WidgetsApp.router(
        color: const Color(0xFF000000),
        routerConfig: MagicRouter.instance.routerConfig,
      ),
    );
    await tester.pumpAndSettle();

    MagicRouter.instance.to('/monitors/4711');
    await tester.pumpAndSettle();

    final RecordedAnalyticsCall screen = fake.screens.last;

    expect(screen.name, '/monitors/:id');
    expect(screen.parameters['location'], '/monitors/:id');
    expect(fake.screens.toString(), isNot(contains('4711')));
  });
}
