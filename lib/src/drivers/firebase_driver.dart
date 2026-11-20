import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';

import 'analytics_driver.dart';

/// The iOS and Android driver, over `firebase_analytics`.
///
/// Reachable only through the `dart.library.io` arm of the driver factory, so
/// Firebase is never initialised on web. The factory is synchronous, so the
/// first call initialises Firebase (when no app exists yet), sets consent and
/// enables collection, once, behind a memoised future.
///
/// The host's native config switches collection off by default, so nothing is
/// collected until this driver enables it; `ad_storage`, `ad_user_data` and
/// `ad_personalization` are denied on every start and nothing flips them.
class FirebaseDriver implements AnalyticsDriver {
  /// Creates the driver.
  ///
  /// [options] is read only when Firebase has to be initialised. [analytics]
  /// replaces `FirebaseAnalytics.instance` and skips the Firebase
  /// initialisation, which lets a test run without a Firebase app.
  FirebaseDriver({required this._options, this._analytics});

  final FirebaseOptions Function() _options;

  FirebaseAnalytics? _analytics;

  Future<FirebaseAnalytics>? _ready;

  bool _optedOut = false;

  /// The user property names set and not yet cleared, so [reset] can null each.
  final Set<String> _userPropertyNames = <String>{};

  /// The default parameters currently set; the SDK takes the whole map.
  final Map<String, Object> _defaultParams = <String, Object>{};

  @override
  Future<void> logEvent(String name, Map<String, Object> parameters) async {
    final FirebaseAnalytics sdk = await _sdk();

    await sdk.logEvent(name: name, parameters: parameters);
  }

  /// Sends `screen_view` for the page [name], which is the route pattern.
  ///
  /// [location] and [referrer] are not Firebase parameters and are dropped.
  @override
  Future<void> logScreen({
    required String name,
    String? location,
    String? referrer,
  }) async {
    final FirebaseAnalytics sdk = await _sdk();

    await sdk.logScreenView(screenName: name, screenClass: name);
  }

  @override
  Future<void> setUserId(String? userId) async {
    final FirebaseAnalytics sdk = await _sdk();

    await sdk.setUserId(id: userId);
  }

  @override
  Future<void> setUserProperty(String name, String? value) async {
    final FirebaseAnalytics sdk = await _sdk();

    if (value == null) {
      _userPropertyNames.remove(name);
    } else {
      _userPropertyNames.add(name);
    }

    await sdk.setUserProperty(name: name, value: value);
  }

  @override
  Future<void> setDefaultParams(Map<String, Object?> parameters) async {
    final FirebaseAnalytics sdk = await _sdk();

    for (final MapEntry<String, Object?> entry in parameters.entries) {
      final Object? value = entry.value;

      if (value == null) {
        _defaultParams.remove(entry.key);
      } else {
        _defaultParams[entry.key] = value;
      }
    }

    await sdk.setDefaultEventParameters(_defaultParamsOrNull());
  }

  @override
  Future<void> setOptOut(bool optedOut) async {
    _optedOut = optedOut;

    final FirebaseAnalytics sdk = await _sdk();

    await sdk.setAnalyticsCollectionEnabled(!optedOut);
  }

  @override
  Future<String?> clientId() async {
    final FirebaseAnalytics sdk = await _sdk();

    return sdk.appInstanceId;
  }

  /// Nulls the user id, every property set and the default parameters.
  ///
  /// Never `resetAnalyticsData`: it rotates the app instance id, and the
  /// device stays the same across a sign-out.
  @override
  Future<void> reset() async {
    final FirebaseAnalytics sdk = await _sdk();

    await sdk.setUserId(id: null);

    for (final String name in _userPropertyNames.toList()) {
      await sdk.setUserProperty(name: name, value: null);
    }

    _userPropertyNames.clear();
    _defaultParams.clear();

    await sdk.setDefaultEventParameters(null);
  }

  Future<FirebaseAnalytics> _sdk() => _ready ??= _initialise();

  Future<FirebaseAnalytics> _initialise() async {
    // 1. A host that already initialised Firebase keeps its app; the options
    //    are only for the one that did not.
    if (_analytics == null) {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: _options());
      }

      _analytics = FirebaseAnalytics.instance;
    }

    final FirebaseAnalytics sdk = _analytics!;

    // 2. Ads stay denied, whatever the project's Firebase defaults are.
    await sdk.setConsent(
      analyticsStorageConsentGranted: true,
      adStorageConsentGranted: false,
      adUserDataConsentGranted: false,
      adPersonalizationSignalsConsentGranted: false,
    );

    // 3. Native config ships collection off, so a device that has not opted
    //    out is switched on here.
    if (!_optedOut) {
      await sdk.setAnalyticsCollectionEnabled(true);
    }

    return sdk;
  }

  /// The defaults as the SDK takes them: null clears them all.
  Map<String, Object?>? _defaultParamsOrNull() =>
      _defaultParams.isEmpty ? null : Map<String, Object?>.of(_defaultParams);
}
