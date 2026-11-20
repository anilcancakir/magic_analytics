import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_analytics/magic_analytics.dart';

import '../helpers/test_helpers.dart';

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

  group('track', () {
    test('hands the event and its parameters to the driver', () async {
      await Analytics.track('monitor_created', {
        'monitor_type': 'http',
        'interval_sec': 60,
      });

      expect(fake.events, hasLength(1));
      expect(fake.events.single.name, 'monitor_created');
      expect(fake.events.single.parameters, {
        'monitor_type': 'http',
        'interval_sec': 60,
      });
    });

    test('scrubs an email or a token out of a string parameter', () async {
      await Analytics.track('link_opened', {
        'link': '/auth/reset-password?token=abc&email=a@b.c',
        'contact': 'jane@example.com',
      });

      final String sent = fake.events.single.parameters.toString();

      expect(sent, isNot(contains('abc')));
      expect(sent, isNot(contains('a@b.c')));
      expect(sent, isNot(contains('jane@example.com')));
    });
  });

  group('screen', () {
    test('scrubs the name, location and referrer', () async {
      await Analytics.screen(
        '/auth/reset-password',
        location: '/auth/reset-password?token=abc&email=a@b.c',
        referrer: '/invite?code=999',
      );

      final RecordedAnalyticsCall call = fake.screens.single;

      expect(call.name, '/auth/reset-password');
      expect(
        call.parameters['location'],
        '/auth/reset-password?token=[Filtered]&email=[Filtered]',
      );
      expect(call.parameters['referrer'], '/invite?code=[Filtered]');
    });
  });

  group('GA4 limits are asserted in debug and nothing is sent', () {
    void expectRejected(Future<void> Function() call) {
      expect(call, throwsA(isA<AssertionError>()));
    }

    test('an event name of 41 characters', () {
      expectRejected(() => Analytics.track('a' * 41));
      expect(fake.calls, isEmpty);
    });

    test('an event name of exactly 40 characters is accepted', () async {
      await Analytics.track('a' * 40);

      expect(fake.events.single.name, 'a' * 40);
    });

    test('an event name that does not start with a letter', () {
      expectRejected(() => Analytics.track('1st_event'));
      expectRejected(() => Analytics.track('_event'));
    });

    test('an event name with characters outside [A-Za-z0-9_]', () {
      expectRejected(() => Analytics.track('monitor-created'));
      expectRejected(() => Analytics.track('monitor created'));
    });

    test('an event name with a reserved prefix', () {
      expectRejected(() => Analytics.track('ga_event'));
      expectRejected(() => Analytics.track('google_event'));
      expectRejected(() => Analytics.track('firebase_event'));
      expectRejected(() => Analytics.track('Firebase_event'));
    });

    test('more than 25 parameters', () {
      expectRejected(
        () => Analytics.track('too_many', {
          for (int i = 0; i < 26; i++) 'p$i': i,
        }),
      );
    });

    test('more than 25 parameters once the default ones are added', () async {
      await Analytics.setDefaultParams({for (int i = 0; i < 20; i++) 'd$i': i});

      expectRejected(
        () =>
            Analytics.track('too_many', {for (int i = 0; i < 6; i++) 'p$i': i}),
      );
      expect(fake.events, isEmpty);
    });

    test('a parameter name of 41 characters', () {
      expectRejected(() => Analytics.track('e', {'p' * 41: 1}));
    });

    test('a string parameter value of 101 characters', () {
      expectRejected(() => Analytics.track('e', {'p': 'v' * 101}));
    });

    test('a parameter value that is neither a string nor a number', () {
      expectRejected(() => Analytics.track('e', {'p': true}));
    });

    test('a user property name of 25 characters', () {
      expectRejected(() => Analytics.setUserProperties({'p' * 25: 'v'}));
    });

    test('a user property value of 37 characters', () {
      expectRejected(() => Analytics.setUserProperties({'plan': 'v' * 37}));
    });

    test('a user id of 257 characters', () {
      expectRejected(() => Analytics.identify('u' * 257));
    });

    test('a user id that carries an email address', () {
      expectRejected(() => Analytics.identify('jane@example.com'));
    });

    test('nothing reached the driver for any rejected call', () {
      expectRejected(() => Analytics.track('a' * 41));
      expectRejected(() => Analytics.identify('u' * 257));

      expect(fake.calls, isEmpty);
    });
  });

  group('opt-out', () {
    test('drops every call except setOptOut, reset and clientId', () async {
      await Analytics.setOptOut(true);
      fake.calls.clear();

      await Analytics.track('monitor_created');
      await Analytics.screen('/monitors/:id', location: '/monitors/:id');
      await Analytics.identify('user-a');
      await Analytics.setUserProperties({'plan': 'pro'});
      await Analytics.setDefaultParams({'team_plan': 'pro'});

      expect(fake.calls, isEmpty);
      expect(Analytics.isOptedOut, isTrue);
    });

    test('forwards the opt-out so the driver stops collecting', () async {
      await Analytics.setOptOut(true);

      expect(fake.calls.single.kind, RecordedCallKind.optOut);
      expect(fake.calls.single.parameters, {'opted_out': true});
    });

    test('still lets reset and clientId through', () async {
      fake.clientIdValue = 'client-1';
      await Analytics.setOptOut(true);
      fake.calls.clear();

      await Analytics.reset();

      expect(fake.calls.map((c) => c.kind), contains(RecordedCallKind.reset));
      expect(await Analytics.clientId(), 'client-1');
    });

    test('an invalid event is not asserted on an opted-out device', () async {
      await Analytics.setOptOut(true);

      await Analytics.track('a' * 41);

      expect(fake.events, isEmpty);
    });

    test('opting back in resumes sending', () async {
      await Analytics.setOptOut(true);
      await Analytics.setOptOut(false);

      await Analytics.track('monitor_created');

      expect(fake.events.single.name, 'monitor_created');
    });
  });

  group('reset', () {
    test('nulls the user id, every property set and the defaults', () async {
      await Analytics.identify('user-a');
      await Analytics.setUserProperties({'plan': 'pro', 'role': 'owner'});
      await Analytics.setDefaultParams({'team_plan': 'pro'});

      await Analytics.reset();

      expect(fake.userId, isNull);
      expect(fake.userProperties, isEmpty);
      expect(fake.defaultParams, isEmpty);
      expect(
        fake.calls
            .where((c) => c.kind == RecordedCallKind.userProperty)
            .map((c) => (c.name, c.parameters['value'])),
        containsAll(<(String, Object?)>[('plan', null), ('role', null)]),
      );
    });

    test('forgets what it nulled, so the next reset nulls nothing', () async {
      await Analytics.setUserProperties({'plan': 'pro'});
      await Analytics.reset();
      fake.calls.clear();

      await Analytics.reset();

      expect(
        fake.calls.where((c) => c.kind == RecordedCallKind.userProperty),
        isEmpty,
      );
    });

    test('an unawaited reset still lands before the next identity', () async {
      await Analytics.identify('user-a');
      await Analytics.setDefaultParams({'team_plan': 'pro'});

      // An auth listener cannot await, so the reset is fired and the app
      // immediately sets the next user's identity.
      unawaited(Analytics.reset());
      await Analytics.identify('user-b');
      await Analytics.setDefaultParams({'team_plan': 'free'});
      await Analytics.track('monitor_created');

      final RecordedAnalyticsCall event = fake.events.single;

      expect(event.userId, 'user-b');
      expect(event.defaultParams, {'team_plan': 'free'});
    });
  });

  group('setUserProperties', () {
    test('a null value removes the property', () async {
      await Analytics.setUserProperties({'plan': 'pro'});
      await Analytics.setUserProperties({'plan': null});

      expect(fake.userProperties, isEmpty);
    });
  });

  group('setDefaultParams', () {
    test('replaces the whole set, clearing keys left out', () async {
      await Analytics.setDefaultParams({'team_plan': 'pro', 'team_size': 3});
      await Analytics.setDefaultParams({'team_plan': 'free'});

      expect(fake.defaultParams, {'team_plan': 'free'});
    });

    test('null clears every default', () async {
      await Analytics.setDefaultParams({'team_plan': 'pro'});
      await Analytics.setDefaultParams(null);

      expect(fake.defaultParams, isEmpty);
    });
  });

  group('a failing driver', () {
    test('never throws into the caller and logs through Log', () async {
      final FakeLogManager log = Log.fake();
      Magic.app.setInstance('analytics', AnalyticsManager(ThrowingDriver()));

      await Analytics.track('monitor_created');
      await Analytics.identify('user-a');
      await Analytics.reset();

      expect(await Analytics.clientId(), isNull);
      expect(log.entries, isNotEmpty);
      expect(
        log.entries.every((e) => e.message.contains('transport down')),
        isTrue,
      );

      Log.unfake();
    });
  });

  group('fake', () {
    test('unfake removes the fake binding', () {
      Analytics.unfake();

      expect(Magic.bound('analytics'), isFalse);
    });
  });
}
