import 'package:flutter/foundation.dart' show ValueNotifier, VoidCallback;
import 'package:magic/magic.dart';

import 'drivers/analytics_driver.dart';
import 'drivers/driver_factory.dart';
import 'drivers/null_driver.dart';
import 'facades/analytics.dart';
import 'observers/analytics_navigator_observer.dart';

/// Wires analytics into a magic application.
///
/// Register it in `lib/config/app.dart`'s `providers` list:
/// `(app) => AnalyticsServiceProvider(app)`.
///
/// CONFIG, read from the `analytics` map when the facade is first used:
///
/// ```dart
/// 'analytics': {
///   // Master switch; anything but true keeps the null driver.
///   'enabled': true,
///   // Web: GTM container and the first-party path that serves it.
///   'gtm': {
///     'container_id': 'GTM-XXXXXXX',
///     'gateway_path': '/metrics',
///   },
///   // iOS and Android: a `FirebaseOptions Function()`, typically
///   // `() => DefaultFirebaseOptions.currentPlatform`. Opaque here; only the
///   // io driver factory casts it.
///   'firebase_options': null,
/// },
/// ```
///
/// [register] binds the `analytics` [AnalyticsManager] over the driver
/// `createAnalyticsDriver` picks for the platform. [boot] adds the page view
/// observer to `MagicRouter` and resets analytics whenever the signed-in user
/// signs out or changes. The app decides what the user id is and calls
/// `Analytics.identify` itself; this provider never identifies anyone.
class AnalyticsServiceProvider extends ServiceProvider {
  /// Creates the provider.
  AnalyticsServiceProvider(super.app);

  /// The auth notifier the sign-out listener is attached to, and the
  /// listener, kept statically so a second boot in the same isolate (a test
  /// suite booting again) replaces the listener instead of adding another.
  static ValueNotifier<int>? _authNotifier;
  static VoidCallback? _authListener;

  @override
  void register() {
    app.singleton('analytics', () => AnalyticsManager(_resolveDriver()));
  }

  @override
  Future<void> boot() async {
    // Added here rather than in `main()` because `MagicRouter` refuses an
    // observer once it has built its `routerConfig`, which happens after
    // every provider booted.
    final bool observing = MagicRouter.instance.observers
        .whereType<AnalyticsNavigatorObserver>()
        .isNotEmpty;

    if (!observing) {
      MagicRouter.instance.addObserver(AnalyticsNavigatorObserver());
    }

    if (Magic.bound('auth')) {
      _resetOnSignOut();
    }
  }

  /// The driver for this platform, or the null driver unless `enabled`.
  AnalyticsDriver _resolveDriver() {
    final Map<String, dynamic> config = Map<String, dynamic>.from(
      Config.get<Map<dynamic, dynamic>>('analytics') ?? const {},
    );

    if (config['enabled'] != true) {
      return const NullDriver();
    }

    return createAnalyticsDriver(config);
  }

  /// Reset analytics whenever the signed-in user goes away or is replaced.
  ///
  /// Follows `Auth.stateNotifier`, which bumps on login, logout, restore and
  /// team switch. Keyed on the user id rather than on each bump, so a team
  /// switch (same user) keeps the identity and the app re-sets the team's
  /// default parameters itself.
  void _resetOnSignOut() {
    Object? signedInAs = Auth.id();

    void listener() {
      final Object? current = Auth.id();

      if (signedInAs != null && current != signedInAs) {
        Analytics.reset();
      }

      signedInAs = current;
    }

    final VoidCallback? previous = _authListener;

    if (previous != null) {
      _authNotifier?.removeListener(previous);
    }

    _authListener = listener;
    _authNotifier = Auth.stateNotifier..addListener(listener);
  }
}
