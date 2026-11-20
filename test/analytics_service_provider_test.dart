import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_analytics/magic_analytics.dart';

import 'helpers/test_helpers.dart';

/// Registers and boots the provider the way `Magic.init` does.
Future<AnalyticsServiceProvider> _bootProvider() async {
  final AnalyticsServiceProvider provider = AnalyticsServiceProvider(Magic.app);

  await Magic.register(provider);
  await provider.boot();

  return provider;
}

void main() {
  setUp(resetMagic);

  tearDown(() {
    Analytics.unfake();
    Auth.unfake();
    MagicRouter.reset();
  });

  group('register', () {
    test('binds a manager over the null driver when unconfigured', () async {
      await _bootProvider();

      expect(
        Magic.make<AnalyticsManager>('analytics').driver,
        isA<NullDriver>(),
      );
    });

    test('keeps the null driver while analytics.enabled is false', () async {
      Config.set('analytics', {
        'enabled': false,
        'gtm': {'container_id': 'GTM-TEST', 'gateway_path': '/metrics'},
      });

      await _bootProvider();

      expect(
        Magic.make<AnalyticsManager>('analytics').driver,
        isA<NullDriver>(),
      );
    });

    test('createAnalyticsDriver answers the null driver off web', () {
      expect(
        createAnalyticsDriver({
          'enabled': true,
          'gtm': {'container_id': 'GTM-TEST', 'gateway_path': '/metrics'},
        }),
        isA<NullDriver>(),
      );
    });
  });

  group('boot', () {
    test('adds the navigator observer to the magic router', () async {
      await _bootProvider();

      expect(
        MagicRouter.instance.observers.whereType<AnalyticsNavigatorObserver>(),
        hasLength(1),
      );
    });

    test('a second boot adds no second observer or listener', () async {
      Auth.fake(user: testUser('user-a'));
      final AnalyticsServiceProvider provider = await _bootProvider();
      final FakeAnalytics fake = Analytics.fake();

      await provider.boot();
      await Auth.logout();
      await drainAnalytics();

      expect(
        MagicRouter.instance.observers.whereType<AnalyticsNavigatorObserver>(),
        hasLength(1),
      );
      expect(
        fake.calls.where((c) => c.kind == RecordedCallKind.reset),
        hasLength(1),
      );
    });

    test('boots without an auth binding', () async {
      await _bootProvider();

      expect(Magic.bound('auth'), isFalse);
    });
  });

  group('sign-out', () {
    test('user A out, user B in: B carries none of A identity', () async {
      Auth.fake();
      await _bootProvider();
      final FakeAnalytics fake = Analytics.fake();

      // 1. User A signs in; the app identifies them and sets team facts.
      await Auth.login({'token': 'a'}, testUser('user-a'));
      await Analytics.identify('user-a');
      await Analytics.setUserProperties({'plan': 'pro'});
      await Analytics.setDefaultParams({'team_plan': 'pro'});
      await Analytics.track('monitor_created');

      // 2. User A signs out; the provider resets on the auth state change.
      await Auth.logout();

      // 3. User B signs in on the same device.
      await Auth.login({'token': 'b'}, testUser('user-b'));
      await Analytics.identify('user-b');
      await Analytics.track('incident_opened');

      final RecordedAnalyticsCall first = fake.events.first;
      final RecordedAnalyticsCall bFirst = fake.events.last;

      expect(first.userId, 'user-a');
      expect(bFirst.name, 'incident_opened');
      expect(bFirst.userId, 'user-b');
      expect(bFirst.userProperties, isEmpty);
      expect(bFirst.defaultParams, isEmpty);
      expect(
        fake.calls
            .map((c) => '${c.kind.name} ${c.name ?? ''} ${c.parameters}')
            .toList(),
        <String>[
          'userId  {user_id: user-a}',
          'userProperty plan {value: pro}',
          'defaultParams  {team_plan: pro}',
          'event monitor_created {}',
          'userId  {user_id: null}',
          'userProperty plan {value: null}',
          'defaultParams  {team_plan: null}',
          'reset  {}',
          'userId  {user_id: user-b}',
          'event incident_opened {}',
        ],
      );
    });

    test('an auth bump for the same user resets nothing', () async {
      Auth.fake(user: testUser('user-a'));
      await _bootProvider();
      final FakeAnalytics fake = Analytics.fake();
      await Analytics.identify('user-a');

      // A team switch bumps the notifier without changing the user.
      Auth.stateNotifier.value++;
      await drainAnalytics();

      expect(
        fake.calls.where((c) => c.kind == RecordedCallKind.reset),
        isEmpty,
      );
      expect(fake.userId, 'user-a');
    });

    test('signing in as another user without a sign-out resets', () async {
      Auth.fake(user: testUser('user-a'));
      await _bootProvider();
      final FakeAnalytics fake = Analytics.fake();
      await Analytics.identify('user-a');
      expect(fake.userId, 'user-a');

      await Auth.login({'token': 'b'}, testUser('user-b'));
      await drainAnalytics();

      expect(fake.userId, isNull);
    });
  });
}
