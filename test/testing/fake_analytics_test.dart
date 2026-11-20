import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_analytics/magic_analytics.dart';

import '../helpers/test_helpers.dart';

void main() {
  setUp(resetMagic);

  tearDown(() {
    Analytics.unfake();
    MagicRouter.reset();
  });

  test('Analytics.fake binds a manager over the returned fake', () {
    final FakeAnalytics fake = Analytics.fake();

    expect(Magic.make<AnalyticsManager>('analytics').driver, same(fake));
  });

  test('records each event with the identity in force when sent', () async {
    final FakeAnalytics fake = Analytics.fake();

    await Analytics.track('before_login');
    await Analytics.identify('user-a');
    await Analytics.setUserProperties({'plan': 'pro'});
    await Analytics.setDefaultParams({'team_plan': 'pro'});
    await Analytics.track('after_login', {'step': 1});

    final RecordedAnalyticsCall before = fake.events.first;
    final RecordedAnalyticsCall after = fake.events.last;

    expect(before.userId, isNull);
    expect(before.userProperties, isEmpty);
    expect(before.defaultParams, isEmpty);
    expect(after.name, 'after_login');
    expect(after.parameters, {'step': 1});
    expect(after.userId, 'user-a');
    expect(after.userProperties, {'plan': 'pro'});
    expect(after.defaultParams, {'team_plan': 'pro'});
  });

  test('a recorded snapshot does not move with later calls', () async {
    final FakeAnalytics fake = Analytics.fake();

    await Analytics.setUserProperties({'plan': 'pro'});
    await Analytics.track('first');
    await Analytics.setUserProperties({'plan': 'free'});

    expect(fake.events.single.userProperties, {'plan': 'pro'});
  });

  test('assertTracked and assertNotTracked read the recorded events', () async {
    final FakeAnalytics fake = Analytics.fake();

    await Analytics.track('monitor_created');

    fake.assertTracked('monitor_created');
    fake.assertNotTracked('monitor_deleted');
    expect(
      () => fake.assertTracked('monitor_deleted'),
      throwsA(isA<AssertionError>()),
    );
    expect(
      () => fake.assertNotTracked('monitor_created'),
      throwsA(isA<AssertionError>()),
    );
  });

  test('assertNothingSent fails once any call reached the driver', () async {
    final FakeAnalytics fake = Analytics.fake();

    fake.assertNothingSent();
    await Analytics.identify('user-a');

    expect(fake.assertNothingSent, throwsA(isA<AssertionError>()));
  });

  test('clientId answers the configured value', () async {
    final FakeAnalytics fake = Analytics.fake()..clientIdValue = 'cid-1';

    expect(await Analytics.clientId(), 'cid-1');
    expect(fake.calls, isEmpty);
  });

  test('unfake restores the binding the provider registered', () {
    Magic.app.singleton(
      'analytics',
      () => AnalyticsManager(const NullDriver()),
    );
    Analytics.fake();

    Analytics.unfake();

    expect(Magic.make<AnalyticsManager>('analytics').driver, isA<NullDriver>());
  });
}
