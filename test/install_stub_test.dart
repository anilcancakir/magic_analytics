import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Locks what the published `analytics.dart` config stub and the install
/// manifest claim, since the stub is copied into an app once and nothing
/// re-checks it afterwards.
void main() {
  final String stub = File('assets/stubs/install/analytics_config.stub')
      .readAsStringSync();
  final String manifest = File('install.yaml').readAsStringSync();

  group('analytics_config.stub', () {
    test('publishes the analytics map the provider reads', () {
      expect(stub, contains("'analytics': {"));
      expect(stub, contains("'enabled': env('ANALYTICS_ENABLED', false)"));
      expect(stub, contains("Env.filled('GTM_CONTAINER_ID', '')"));
      expect(stub, contains("Env.filled('GTM_GATEWAY_PATH', '')"));
      expect(stub, contains("'firebase_options': null"));
    });

    test('is a config factory getter named analyticsConfig', () {
      expect(stub, contains('Map<String, dynamic> get analyticsConfig'));
    });

    test('says firebase_options stays null on web', () {
      expect(stub, contains('DefaultFirebaseOptions.currentPlatform'));
      expect(stub, contains('flutterfire configure --platforms=ios,android'));
      expect(stub, contains('web'));
    });
  });

  group('install.yaml', () {
    test('publishes the stub to lib/config/analytics.dart', () {
      expect(
        manifest,
        contains('install/analytics_config: lib/config/analytics.dart'),
      );
    });

    test('injects the provider and the config factory', () {
      expect(manifest, contains('provider: AnalyticsServiceProvider'));
      expect(manifest, contains('config_factory: analyticsConfig'));
    });

    test('names the native keys that keep ads consent denied', () {
      expect(manifest, contains('GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_STORAGE'));
      expect(manifest, contains('google_analytics_default_allow_ad_storage'));
    });

    test('routes web through a first-party gateway', () {
      expect(manifest, contains('fps.goog'));
    });
  });

  test('the example app carries the stub unchanged', () {
    final String example = File('example/lib/config/analytics.dart')
        .readAsStringSync();

    expect(example, stub);
  });
}
