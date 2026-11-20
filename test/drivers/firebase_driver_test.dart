import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_analytics/src/drivers/driver_factory_io.dart';
import 'package:magic_analytics/src/drivers/firebase_driver.dart';
import 'package:magic_analytics/src/drivers/null_driver.dart';

/// A [FirebaseAnalytics] that records each call it receives, so a test asserts
/// what reached the SDK without a Firebase app or a platform channel.
class _RecordingFirebaseAnalytics extends Fake implements FirebaseAnalytics {
  final List<(String, Map<String, Object?>)> calls =
      <(String, Map<String, Object?>)>[];

  String? instanceId = 'app-instance-1';

  void _record(String method, [Map<String, Object?> arguments = const {}]) =>
      calls.add((method, arguments));

  @override
  Future<String?> get appInstanceId async => instanceId;

  @override
  Future<void> setConsent({
    bool? adStorageConsentGranted,
    bool? analyticsStorageConsentGranted,
    bool? adPersonalizationSignalsConsentGranted,
    bool? adUserDataConsentGranted,
    bool? functionalityStorageConsentGranted,
    bool? personalizationStorageConsentGranted,
    bool? securityStorageConsentGranted,
  }) async => _record('setConsent', <String, Object?>{
    'adStorage': adStorageConsentGranted,
    'analyticsStorage': analyticsStorageConsentGranted,
    'adPersonalization': adPersonalizationSignalsConsentGranted,
    'adUserData': adUserDataConsentGranted,
  });

  @override
  Future<void> setAnalyticsCollectionEnabled(bool enabled) async => _record(
    'setAnalyticsCollectionEnabled',
    <String, Object?>{'enabled': enabled},
  );

  @override
  Future<void> logEvent({
    required String name,
    Map<String, Object>? parameters,
    List<AnalyticsEventItem>? items,
    AnalyticsCallOptions? callOptions,
  }) async => _record('logEvent', <String, Object?>{
    'name': name,
    'parameters': parameters,
  });

  @override
  Future<void> logScreenView({
    String? screenClass,
    String? screenName,
    Map<String, Object>? parameters,
    AnalyticsCallOptions? callOptions,
  }) async => _record('logScreenView', <String, Object?>{
    'screenClass': screenClass,
    'screenName': screenName,
  });

  @override
  Future<void> setUserId({
    String? id,
    AnalyticsCallOptions? callOptions,
  }) async => _record('setUserId', <String, Object?>{'id': id});

  @override
  Future<void> setUserProperty({
    required String name,
    required String? value,
    AnalyticsCallOptions? callOptions,
  }) async => _record('setUserProperty', <String, Object?>{
    'name': name,
    'value': value,
  });

  @override
  Future<void> setDefaultEventParameters(
    Map<String, Object?>? defaultParameters,
  ) async => _record('setDefaultEventParameters', <String, Object?>{
    'parameters': defaultParameters,
  });

  @override
  Future<void> resetAnalyticsData() async => _record('resetAnalyticsData');
}

const FirebaseOptions _options = FirebaseOptions(
  apiKey: 'key',
  appId: 'app',
  messagingSenderId: 'sender',
  projectId: 'project',
);

FirebaseOptions _buildOptions() => _options;

void main() {
  late _RecordingFirebaseAnalytics sdk;
  late FirebaseDriver driver;

  setUp(() {
    sdk = _RecordingFirebaseAnalytics();
    driver = FirebaseDriver(options: _buildOptions, analytics: sdk);
  });

  List<String> methods() => sdk.calls.map((call) => call.$1).toList();

  Iterable<Map<String, Object?>> argumentsOf(String method) =>
      sdk.calls.where((call) => call.$1 == method).map((call) => call.$2);

  group('first use', () {
    test('sets consent with every ad signal denied, then enables collection, '
        'once', () async {
      await driver.logEvent('monitor_created', <String, Object>{});
      await driver.logEvent('monitor_created', <String, Object>{});

      expect(argumentsOf('setConsent'), <Map<String, Object?>>[
        <String, Object?>{
          'adStorage': false,
          'analyticsStorage': true,
          'adPersonalization': false,
          'adUserData': false,
        },
      ]);
      expect(argumentsOf('setAnalyticsCollectionEnabled'), <Object>[
        <String, Object?>{'enabled': true},
      ]);
      expect(methods().take(3), <String>[
        'setConsent',
        'setAnalyticsCollectionEnabled',
        'logEvent',
      ]);
    });

    test('keeps collection off when the device opted out before it', () async {
      await driver.setOptOut(true);
      await driver.logEvent('monitor_created', <String, Object>{});

      expect(argumentsOf('setAnalyticsCollectionEnabled'), <Object>[
        <String, Object?>{'enabled': false},
      ]);
    });
  });

  group('opt-out', () {
    test('disables collection', () async {
      await driver.setOptOut(true);

      expect(
        argumentsOf('setAnalyticsCollectionEnabled').last,
        <String, Object?>{'enabled': false},
      );
    });

    test('resumes collection', () async {
      await driver.setOptOut(true);
      await driver.setOptOut(false);

      expect(
        argumentsOf('setAnalyticsCollectionEnabled').last,
        <String, Object?>{'enabled': true},
      );
    });
  });

  group('events and screens', () {
    test('logEvent forwards the name and parameters', () async {
      await driver.logEvent('monitor_created', <String, Object>{
        'monitor_type': 'http',
      });

      expect(argumentsOf('logEvent'), <Map<String, Object?>>[
        <String, Object?>{
          'name': 'monitor_created',
          'parameters': <String, Object>{'monitor_type': 'http'},
        },
      ]);
    });

    test('screen sends logScreenView with the pattern name', () async {
      await driver.logScreen(
        name: '/monitors/:id',
        location: '/monitors/:id',
        referrer: '/monitors',
      );

      expect(argumentsOf('logScreenView'), <Map<String, Object?>>[
        <String, Object?>{
          'screenClass': '/monitors/:id',
          'screenName': '/monitors/:id',
        },
      ]);
    });
  });

  group('identity', () {
    test('setUserId forwards the id', () async {
      await driver.setUserId('9f1c');

      expect(argumentsOf('setUserId'), <Map<String, Object?>>[
        <String, Object?>{'id': '9f1c'},
      ]);
    });

    test('setUserProperty forwards the name and value', () async {
      await driver.setUserProperty('locale', 'tr');

      expect(argumentsOf('setUserProperty'), <Map<String, Object?>>[
        <String, Object?>{'name': 'locale', 'value': 'tr'},
      ]);
    });

    test('clientId is the app instance id', () async {
      expect(await driver.clientId(), 'app-instance-1');
    });
  });

  group('default parameters', () {
    test('merges into one map and drops a key set to null', () async {
      await driver.setDefaultParams(<String, Object?>{
        'team_plan': 'pro',
        'team_size': 3,
      });
      await driver.setDefaultParams(<String, Object?>{
        'team_plan': null,
        'team_region': 'eu',
      });

      expect(argumentsOf('setDefaultEventParameters'), <Map<String, Object?>>[
        <String, Object?>{
          'parameters': <String, Object?>{'team_plan': 'pro', 'team_size': 3},
        },
        <String, Object?>{
          'parameters': <String, Object?>{'team_size': 3, 'team_region': 'eu'},
        },
      ]);
    });

    test('clears the SDK defaults once the last key is removed', () async {
      await driver.setDefaultParams(<String, Object?>{'team_plan': 'pro'});
      await driver.setDefaultParams(<String, Object?>{'team_plan': null});

      expect(argumentsOf('setDefaultEventParameters').last, <String, Object?>{
        'parameters': null,
      });
    });
  });

  group('reset', () {
    test('nulls the user id and every user property that was set', () async {
      await driver.setUserId('9f1c');
      await driver.setUserProperty('locale', 'tr');
      await driver.setUserProperty('theme', 'dark');
      sdk.calls.clear();

      await driver.reset();

      expect(argumentsOf('setUserId'), <Map<String, Object?>>[
        <String, Object?>{'id': null},
      ]);
      expect(argumentsOf('setUserProperty'), <Map<String, Object?>>[
        <String, Object?>{'name': 'locale', 'value': null},
        <String, Object?>{'name': 'theme', 'value': null},
      ]);
    });

    test('skips a property already cleared before the reset', () async {
      await driver.setUserProperty('locale', 'tr');
      await driver.setUserProperty('locale', null);
      sdk.calls.clear();

      await driver.reset();

      expect(argumentsOf('setUserProperty'), isEmpty);
    });

    test('clears the default parameters', () async {
      await driver.setDefaultParams(<String, Object?>{'team_plan': 'pro'});
      sdk.calls.clear();

      await driver.reset();

      expect(argumentsOf('setDefaultEventParameters'), <Map<String, Object?>>[
        <String, Object?>{'parameters': null},
      ]);
    });

    test(
      'never resets the analytics data, which rotates the client id',
      () async {
        await driver.setUserProperty('locale', 'tr');
        await driver.reset();

        expect(methods(), isNot(contains('resetAnalyticsData')));
        expect(await driver.clientId(), 'app-instance-1');
      },
    );
  });

  group('createAnalyticsDriver', () {
    test('answers the null driver when firebase_options is unset', () {
      expect(
        createAnalyticsDriver(<String, dynamic>{'enabled': true}),
        isA<NullDriver>(),
      );
    });

    test('answers the null driver when firebase_options is not a function', () {
      expect(
        createAnalyticsDriver(<String, dynamic>{'firebase_options': 'nope'}),
        isA<NullDriver>(),
      );
    });

    test('answers the Firebase driver when firebase_options is set', () {
      expect(
        createAnalyticsDriver(<String, dynamic>{
          'firebase_options': _buildOptions,
        }),
        isA<FirebaseDriver>(),
      );
    });
  });
}
