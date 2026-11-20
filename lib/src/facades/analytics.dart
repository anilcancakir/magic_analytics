import 'package:flutter/foundation.dart' show debugPrint;
import 'package:magic/magic.dart';

import '../drivers/analytics_driver.dart';
import '../support/url_scrubber.dart';
import '../testing/fake_analytics.dart';

/// The Analytics facade: static access to the [AnalyticsManager] bound as
/// `analytics` by `AnalyticsServiceProvider`.
///
/// ```dart
/// Analytics.identify(user.uuid);
/// Analytics.setDefaultParams({'team_plan': team.plan});
/// Analytics.track('monitor_created', {'monitor_type': 'http'});
/// ```
///
/// Every call returns a future that never fails: await it in a test, ignore
/// it in app code.
class Analytics {
  Analytics._();

  static AnalyticsManager get _manager =>
      Magic.make<AnalyticsManager>('analytics');

  /// Send the event [name] with [parameters]; see [AnalyticsManager.track].
  static Future<void> track(
    String name, [
    Map<String, Object> parameters = const <String, Object>{},
  ]) => _manager.track(name, parameters);

  /// Send a page view; see [AnalyticsManager.screen].
  static Future<void> screen(
    String name, {
    String? location,
    String? referrer,
  }) => _manager.screen(name, location: location, referrer: referrer);

  /// Set the GA4 user id; see [AnalyticsManager.identify].
  static Future<void> identify(String userId) => _manager.identify(userId);

  /// Set user-level properties; see [AnalyticsManager.setUserProperties].
  static Future<void> setUserProperties(Map<String, String?> properties) =>
      _manager.setUserProperties(properties);

  /// Replace the parameters sent with every event; see
  /// [AnalyticsManager.setDefaultParams].
  static Future<void> setDefaultParams(Map<String, Object>? parameters) =>
      _manager.setDefaultParams(parameters);

  /// Stop or resume collection on this device; see
  /// [AnalyticsManager.setOptOut].
  static Future<void> setOptOut(bool optedOut) => _manager.setOptOut(optedOut);

  /// Whether this device has opted out of analytics.
  static bool get isOptedOut => _manager.isOptedOut;

  /// Forget the signed-in user; see [AnalyticsManager.reset].
  static Future<void> reset() => _manager.reset();

  /// The GA4 client id, or null; see [AnalyticsManager.clientId].
  static Future<String?> clientId() => _manager.clientId();

  /// Bind a manager over a [FakeAnalytics] driver and return the fake.
  ///
  /// The manager is the real one, so validation, scrubbing, opt-out and reset
  /// apply exactly as in the app; the fake records what reached the driver.
  ///
  /// ```dart
  /// final fake = Analytics.fake();
  /// await Analytics.track('monitor_created');
  /// fake.assertTracked('monitor_created');
  /// ```
  static FakeAnalytics fake() {
    final FakeAnalytics driver = FakeAnalytics();

    Magic.app.setInstance('analytics', AnalyticsManager(driver));

    return driver;
  }

  /// Remove the fake; the next call resolves the provider's binding again.
  static void unfake() => Magic.app.removeInstance('analytics');
}

/// Validates, scrubs and gates every analytics call, then hands it to one
/// [AnalyticsDriver] for transport.
///
/// GA4 LIMITS. A call that breaks one fails an `assert` in debug, so a test
/// or a debug run stops at the call site; in release the call is dropped and
/// the reason logged through magic's `Log`. Nothing invalid reaches a driver.
///
/// ORDER. Driver calls run one at a time, in call order, on a queue: an auth
/// listener cannot await `reset()`, and without the queue the next user's
/// `setDefaultParams` could reach the driver before the previous user's were
/// cleared.
///
/// FAILURE. A driver error is caught here, logged and never rethrown, so an
/// analytics call never throws into UI flow.
class AnalyticsManager {
  /// Creates a manager sending through [driver].
  AnalyticsManager(this.driver);

  /// The transport every accepted call is handed to.
  final AnalyticsDriver driver;

  /// The longest event name, parameter name or default parameter name.
  static const int maxNameLength = 40;

  /// The most parameters one event may carry, default parameters included.
  static const int maxParameters = 25;

  /// The longest string parameter value.
  static const int maxParameterValueLength = 100;

  /// The longest user property name.
  static const int maxUserPropertyNameLength = 24;

  /// The longest user property value.
  static const int maxUserPropertyValueLength = 36;

  /// The longest user id.
  static const int maxUserIdLength = 256;

  static const List<String> _reservedPrefixes = <String>[
    'ga_',
    'google_',
    'firebase_',
  ];

  static final RegExp _namePattern = RegExp(r'^[A-Za-z][A-Za-z0-9_]*$');

  bool _optedOut = false;

  /// The user properties set since the last [reset], so it can null each.
  final Set<String> _userPropertyNames = <String>{};

  /// The default parameter keys currently set, so a replacement or a [reset]
  /// can null the ones that go.
  final Set<String> _defaultParamNames = <String>{};

  Future<void> _queue = Future<void>.value();

  /// Whether this device has opted out.
  bool get isOptedOut => _optedOut;

  /// Send the event [name] with [parameters].
  ///
  /// [name] is letters, digits and underscores, starts with a letter, is at
  /// most [maxNameLength] long and has no `ga_`, `google_` or `firebase_`
  /// prefix. [parameters] values are strings or numbers; a string value is
  /// scrubbed through [UrlScrubber] and is at most [maxParameterValueLength]
  /// long afterwards. Together with the default parameters there are at most
  /// [maxParameters].
  Future<void> track(
    String name, [
    Map<String, Object> parameters = const <String, Object>{},
  ]) {
    if (_optedOut) {
      return Future<void>.value();
    }

    // 1. Scrub first, so the limits apply to what is actually sent.
    final Map<String, Object> scrubbed = _scrubParameters(parameters);
    final int total =
        scrubbed.length +
        _defaultParamNames.where((key) => !scrubbed.containsKey(key)).length;

    // 2. Reject anything GA4 would refuse or silently truncate.
    final String? violation =
        _nameViolation('event name', name, maxNameLength) ??
        (total > maxParameters
            ? 'event "$name" carries $total parameters, more than '
                  '$maxParameters with the defaults'
            : null) ??
        _parametersViolation(scrubbed);

    if (!_accepts(violation)) {
      return Future<void>.value();
    }

    // 3. Hand it over in call order.
    return _send('logEvent', (driver) => driver.logEvent(name, scrubbed));
  }

  /// Send a page view for the page [name] (its title), at [location], arrived
  /// at from [referrer]. All three are scrubbed through [UrlScrubber].
  Future<void> screen(String name, {String? location, String? referrer}) {
    if (_optedOut) {
      return Future<void>.value();
    }

    final String scrubbedName = UrlScrubber.scrub(name);
    final String? scrubbedLocation = _scrubOrNull(location);
    final String? scrubbedReferrer = _scrubOrNull(referrer);

    return _send(
      'logScreen',
      (driver) => driver.logScreen(
        name: scrubbedName,
        location: scrubbedLocation,
        referrer: scrubbedReferrer,
      ),
    );
  }

  /// Set the GA4 user id to [userId], the user's opaque id (a UUID).
  ///
  /// At most [maxUserIdLength] long, and never anything [UrlScrubber] would
  /// mask: an email address is not an id. Cleared by [reset].
  Future<void> identify(String userId) {
    if (_optedOut) {
      return Future<void>.value();
    }

    final String? violation = userId.isEmpty
        ? 'user id is empty'
        : userId.length > maxUserIdLength
        ? 'user id is longer than $maxUserIdLength characters'
        : UrlScrubber.scrub(userId) != userId
        ? 'user id carries an email address or a token'
        : null;

    if (!_accepts(violation)) {
      return Future<void>.value();
    }

    return _send('setUserId', (driver) => driver.setUserId(userId));
  }

  /// Set user-level [properties]; a null value clears that property.
  ///
  /// Only facts about the USER belong here; team facts go through
  /// [setDefaultParams]. A name is at most [maxUserPropertyNameLength] long
  /// and follows the event-name rules; a value is scrubbed and at most
  /// [maxUserPropertyValueLength] long. Every property set is nulled by
  /// [reset].
  Future<void> setUserProperties(Map<String, String?> properties) {
    if (_optedOut) {
      return Future<void>.value();
    }

    final Map<String, String?> scrubbed = <String, String?>{
      for (final MapEntry<String, String?> entry in properties.entries)
        entry.key: _scrubOrNull(entry.value),
    };

    if (!_accepts(_userPropertiesViolation(scrubbed))) {
      return Future<void>.value();
    }

    Future<void> sent = Future<void>.value();

    for (final MapEntry<String, String?> entry in scrubbed.entries) {
      if (entry.value == null) {
        _userPropertyNames.remove(entry.key);
      } else {
        _userPropertyNames.add(entry.key);
      }

      sent = _send(
        'setUserProperty',
        (driver) => driver.setUserProperty(entry.key, entry.value),
      );
    }

    return sent;
  }

  /// Replace the parameters sent with every later event by [parameters];
  /// null clears them all.
  ///
  /// This is where team facts go (a plan, a team size), never into user
  /// properties. Keys and values follow the [track] rules. Cleared by
  /// [reset].
  Future<void> setDefaultParams(Map<String, Object>? parameters) {
    if (_optedOut) {
      return Future<void>.value();
    }

    final Map<String, Object> scrubbed = _scrubParameters(
      parameters ?? const <String, Object>{},
    );
    final String? violation = scrubbed.length > maxParameters
        ? '${scrubbed.length} default parameters, more than $maxParameters'
        : _parametersViolation(scrubbed);

    if (!_accepts(violation)) {
      return Future<void>.value();
    }

    // A key left out of the new set is sent as null, since the driver merges.
    final Map<String, Object?> update = <String, Object?>{
      for (final String key in _defaultParamNames)
        if (!scrubbed.containsKey(key)) key: null,
      ...scrubbed,
    };

    _defaultParamNames
      ..clear()
      ..addAll(scrubbed.keys);

    if (update.isEmpty) {
      return Future<void>.value();
    }

    return _send(
      'setDefaultParams',
      (driver) => driver.setDefaultParams(update),
    );
  }

  /// Stop ([optedOut] true) or resume collection on this device.
  ///
  /// Forwarded to the driver either way, so it can stop collecting. While
  /// opted out every call except [setOptOut], [reset] and [clientId] is a
  /// no-op that reaches no driver.
  Future<void> setOptOut(bool optedOut) {
    _optedOut = optedOut;

    return _send('setOptOut', (driver) => driver.setOptOut(optedOut));
  }

  /// Forget the signed-in user: null the user id, every user property set
  /// since the last reset and every default parameter, then let the driver
  /// clear what is left. Runs on an opted-out device too.
  ///
  /// `AnalyticsServiceProvider` calls this when the auth user signs out or
  /// changes, so the next user's events carry none of this one's identity.
  Future<void> reset() {
    // 1. Take the bookkeeping now, so a call made right after this one starts
    //    from a clean slate even before the driver has caught up.
    final List<String> properties = _userPropertyNames.toList();
    final Map<String, Object?> defaults = <String, Object?>{
      for (final String key in _defaultParamNames) key: null,
    };

    _userPropertyNames.clear();
    _defaultParamNames.clear();

    // 2. One queued call per step, so a failing step does not skip the rest.
    _send('setUserId', (driver) => driver.setUserId(null));

    for (final String name in properties) {
      _send('setUserProperty', (driver) => driver.setUserProperty(name, null));
    }

    if (defaults.isNotEmpty) {
      _send('setDefaultParams', (driver) => driver.setDefaultParams(defaults));
    }

    // 3. The queue runs in order, so the last call settling means all have.
    return _send('reset', (driver) => driver.reset());
  }

  /// The GA4 client id, or null when the driver has none or fails.
  Future<String?> clientId() async {
    await _queue;

    try {
      return await driver.clientId();
    } catch (error, stackTrace) {
      _log('clientId failed: $error', stackTrace);

      return null;
    }
  }

  /// Queue [call] behind every earlier driver call. The returned future
  /// completes once it ran, and never fails.
  Future<void> _send(
    String operation,
    Future<void> Function(AnalyticsDriver driver) call,
  ) {
    return _queue = _queue.then((_) async {
      try {
        await call(driver);
      } catch (error, stackTrace) {
        _log('$operation failed: $error', stackTrace);
      }
    });
  }

  /// Whether a call with [violation] (null when valid) may proceed.
  ///
  /// Asserts in debug; drops with a log line in release, where asserts are
  /// compiled out.
  bool _accepts(String? violation) {
    if (violation == null) {
      return true;
    }

    _log('dropped a call that breaks a GA4 limit: $violation');
    assert(false, '[analytics] $violation');

    return false;
  }

  Map<String, Object> _scrubParameters(Map<String, Object> parameters) {
    return <String, Object>{
      for (final MapEntry<String, Object> entry in parameters.entries)
        entry.key: entry.value is String
            ? UrlScrubber.scrub(entry.value as String)
            : entry.value,
    };
  }

  String? _scrubOrNull(String? text) =>
      text == null ? null : UrlScrubber.scrub(text);

  String? _parametersViolation(Map<String, Object> parameters) {
    for (final MapEntry<String, Object> entry in parameters.entries) {
      final String? violation =
          _nameViolation('parameter name', entry.key, maxNameLength) ??
          _parameterValueViolation(entry.key, entry.value);

      if (violation != null) {
        return violation;
      }
    }

    return null;
  }

  String? _parameterValueViolation(String key, Object value) {
    if (value is String) {
      return value.length > maxParameterValueLength
          ? 'parameter "$key" is longer than $maxParameterValueLength '
                'characters'
          : null;
    }

    return value is num
        ? null
        : 'parameter "$key" is a ${value.runtimeType}, not a string or number';
  }

  String? _userPropertiesViolation(Map<String, String?> properties) {
    for (final MapEntry<String, String?> entry in properties.entries) {
      final String? value = entry.value;
      final String? violation =
          _nameViolation(
            'user property name',
            entry.key,
            maxUserPropertyNameLength,
          ) ??
          (value != null && value.length > maxUserPropertyValueLength
              ? 'user property "${entry.key}" is longer than '
                    '$maxUserPropertyValueLength characters'
              : null);

      if (violation != null) {
        return violation;
      }
    }

    return null;
  }

  /// Why [name] is not a valid GA4 [kind], or null when it is.
  String? _nameViolation(String kind, String name, int maxLength) {
    if (name.length > maxLength) {
      return '$kind "$name" is longer than $maxLength characters';
    }

    if (!_namePattern.hasMatch(name)) {
      return '$kind "$name" must start with a letter and hold only letters, '
          'digits and underscores';
    }

    final String lower = name.toLowerCase();

    if (_reservedPrefixes.any(lower.startsWith)) {
      return '$kind "$name" uses a reserved prefix';
    }

    return null;
  }

  /// Log through magic's `Log` when one is bound, `debugPrint` otherwise, so a
  /// host with no logging configured still sees the failure.
  void _log(String message, [StackTrace? stackTrace]) {
    final String line = '[analytics] $message';

    if (Magic.bound('log')) {
      Log.warning(line, <String, String>{
        if (stackTrace != null) 'stackTrace': stackTrace.toString(),
      });

      return;
    }

    debugPrint(stackTrace == null ? line : '$line\n$stackTrace');
  }
}
