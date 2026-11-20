import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'analytics_driver.dart';

/// The web driver: GA4 through a Google Tag Manager container served from a
/// first-party gateway path, never from `googletagmanager.com`.
///
/// LAZY LOAD. Nothing touches the page until the first call that sends
/// something (`logEvent`, `logScreen`, a non-null `setUserId` or
/// `setUserProperty`, `setDefaultParams`), so a device that opted out never
/// loads the container and never gets a `dataLayer`. Then, in order: an inline
/// script defines `window.dataLayer` and the canonical `gtag` shim, defaults
/// consent (analytics granted, every ad signal denied), pre-seeds
/// `page_location` and `page_referrer` with the origin alone and pushes
/// `gtm.start`; only after that the loader
/// `<script async src="/<gateway>/?id=<id>">` is appended. The shim is real
/// JavaScript on purpose: GTM ignores a consent command pushed as a plain
/// array or object, it needs the `arguments` object `gtag()` pushes. The
/// pre-seed keeps the Google tag from falling back to the real
/// `document.location`, which may carry a token, before the first page view.
///
/// DATA LAYER SHAPE, read by the data layer variables the container defines
/// (its GA4 config sets `send_page_view` to false):
///
/// - `logScreen`: `{event: 'page_view', page_title, page_location,
///   page_referrer}`, both locations built from the route PATTERN on the
///   page's origin, so the real URL (which may carry a token) never leaves.
///   The first page's referrer is the origin root, never null.
/// - `logEvent`: `{event: <name>, ...parameters}`, then a second push that
///   puts each of those parameter keys back to the value this driver holds
///   for it (user id, user properties, page fields, default parameters), or
///   to null when it holds none. The data layer is a merged model, not a queue: without
///   that second push a parameter of one event would reach every later event
///   that reads the key, and an event parameter named like a default would
///   replace the default for good.
/// - `setUserId`: `{user_id: <id or null>}`.
/// - `setUserProperty`: `{user_properties: {<name>: <value or null>}}`,
///   nested, as the data layer merges it key by key.
/// - `setDefaultParams`: the merged keys flat; the data layer keeps them for
///   every later push, and a null removes the key.
///
/// OPT OUT. Opting out after the container loaded pushes a consent update
/// that denies `analytics_storage` and stops every send; opting back in
/// grants it again. `reset` clears the identity this driver pushed and never
/// touches the `_ga` cookie, so the client id survives a sign out.
class GtmWebDriver implements AnalyticsDriver {
  /// Creates a driver loading [containerId] from [gatewayPath], a first-party
  /// path segment written `f86e269b`, `/f86e269b` or `/f86e269b/`.
  GtmWebDriver({required String containerId, required String gatewayPath})
    : _loaderSrc =
          '/${Uri.encodeComponent(_trimSlashes(gatewayPath))}/'
          '?id=${Uri.encodeQueryComponent(containerId)}';

  /// The driver for the `analytics` config map, or null when `gtm.container_id`
  /// or `gtm.gateway_path` is missing or empty: a container is never loaded
  /// from Google's own host.
  static GtmWebDriver? fromConfig(Map<String, dynamic> config) {
    final Object? gtm = config['gtm'];

    if (gtm is! Map) {
      return null;
    }

    final String containerId = '${gtm['container_id'] ?? ''}'.trim();
    final String gatewayPath = _trimSlashes('${gtm['gateway_path'] ?? ''}');

    if (containerId.isEmpty || gatewayPath.isEmpty) {
      return null;
    }

    return GtmWebDriver(containerId: containerId, gatewayPath: gatewayPath);
  }

  static const String _marker = 'data-magic-analytics';

  // Consent for ads is never granted: no config or call may flip these.
  //
  // The page fields are pre-seeded with the origin only: until the first
  // page view is pushed, a data layer variable bound to `page_location` would
  // be undefined and the Google tag would fall back to `document.location`,
  // which can carry a reset token or an invitation path.
  static const String _bootstrap = '''
(function () {
  window.dataLayer = window.dataLayer || [];
  function gtag() { window.dataLayer.push(arguments); }
  window.gtag = gtag;
  gtag('consent', 'default', {
    analytics_storage: 'granted',
    ad_storage: 'denied',
    ad_user_data: 'denied',
    ad_personalization: 'denied'
  });
  window.dataLayer.push({
    page_location: location.origin + '/',
    page_referrer: location.origin + '/'
  });
  window.dataLayer.push({'gtm.start': Date.now(), event: 'gtm.js'});
})();
''';

  static final RegExp _gaCookie = RegExp(
    r'(?:^|;\s*)_ga=GA\d+\.\d+\.(\d+\.\d+)',
  );

  final String _loaderSrc;

  /// The user properties currently pushed, by name.
  final Map<String, String> _userProperties = <String, String>{};

  /// The keys of the default parameters currently pushed; `reset` nulls them.
  final Set<String> _defaultParamNames = <String>{};

  /// The last value pushed outside an event for each flat key (the user id,
  /// the page fields, the default parameters), so it mirrors the data layer
  /// model; a key pushed as null is absent.
  final Map<String, Object> _held = <String, Object>{};

  bool _loaded = false;

  bool _optedOut = false;

  @override
  Future<void> logEvent(String name, Map<String, Object> parameters) async {
    if (_optedOut) {
      return;
    }

    _send(<String, Object?>{...parameters, 'event': name});

    if (parameters.isNotEmpty) {
      _push(<String, Object?>{
        for (final String key in parameters.keys) key: _heldValue(key),
      });
    }
  }

  @override
  Future<void> logScreen({
    required String name,
    String? location,
    String? referrer,
  }) async {
    final Map<String, String> fields = <String, String>{
      'page_title': name,
      'page_location': _onOrigin(location ?? '/'),
      // Never null: gtag would fall back to `document.referrer`.
      'page_referrer': _onOrigin(referrer ?? '/'),
    };

    _send(<String, Object?>{'event': 'page_view', ...fields}, hold: true);
  }

  @override
  Future<void> setUserId(String? userId) async {
    final Map<String, Object?> push = <String, Object?>{'user_id': userId};

    userId == null ? _clear(push, hold: true) : _send(push, hold: true);
  }

  @override
  Future<void> setUserProperty(String name, String? value) async {
    final Map<String, Object?> push = <String, Object?>{
      'user_properties': <String, Object?>{name: value},
    };

    if (value == null) {
      _userProperties.remove(name);
      _clear(push, hold: true);

      return;
    }

    _userProperties[name] = value;
    _send(push, hold: true);
  }

  @override
  Future<void> setDefaultParams(Map<String, Object?> parameters) async {
    for (final MapEntry<String, Object?> entry in parameters.entries) {
      entry.value == null
          ? _defaultParamNames.remove(entry.key)
          : _defaultParamNames.add(entry.key);
    }

    // A set of nulls only removes keys, so it must not load the container.
    parameters.values.any((value) => value != null)
        ? _send(parameters, hold: true)
        : _clear(parameters, hold: true);
  }

  @override
  Future<void> setOptOut(bool optedOut) async {
    if (_optedOut == optedOut) {
      return;
    }

    _optedOut = optedOut;

    if (_loaded) {
      _gtag('consent', 'update', <String, Object?>{
        'analytics_storage': optedOut ? 'denied' : 'granted',
      });
    }
  }

  @override
  Future<String?> clientId() async {
    return _gaCookie.firstMatch(web.document.cookie)?.group(1);
  }

  @override
  Future<void> reset() async {
    final Map<String, Object?> push = <String, Object?>{
      'user_id': null,
      if (_userProperties.isNotEmpty)
        'user_properties': <String, Object?>{
          for (final String name in _userProperties.keys) name: null,
        },
      for (final String key in _defaultParamNames) key: null,
    };

    _clear(push, hold: true);
    _userProperties.clear();
    _defaultParamNames.clear();
  }

  /// Record [data], a push that reached the data layer outside an event, so
  /// `_held` keeps mirroring the model: flat keys by value, `user_properties`
  /// merged key by key as the data layer merges it.
  void _hold(Map<String, Object?> data) {
    for (final MapEntry<String, Object?> entry in data.entries) {
      final Object? value = entry.value;

      // The event name is per push, never part of the model a later event reads.
      if (entry.key == 'event') {
        continue;
      }

      if (entry.key == 'user_properties' && value is Map<String, Object?>) {
        // A flat value held under the same key is replaced, not merged into.
        final Object? previous = _held['user_properties'];
        final Map<String, Object> properties = <String, Object>{
          if (previous is Map<String, Object>) ...previous,
        };

        for (final MapEntry<String, Object?> property in value.entries) {
          final Object? propertyValue = property.value;

          propertyValue == null
              ? properties.remove(property.key)
              : properties[property.key] = propertyValue;
        }

        properties.isEmpty
            ? _held.remove('user_properties')
            : _held['user_properties'] = properties;

        continue;
      }

      value == null ? _held.remove(entry.key) : _held[entry.key] = value;
    }
  }

  /// The value the data layer held for [key] before an event shadowed it;
  /// null for an event-only key.
  Object? _heldValue(String key) => _held[key];

  /// Push [data], loading the container first when this is the first send.
  /// Does nothing while opted out. [hold] records a push made outside an
  /// event once it has reached the data layer.
  void _send(Map<String, Object?> data, {bool hold = false}) {
    if (_optedOut) {
      return;
    }

    _ensureLoaded();
    _push(data);

    if (hold) {
      _hold(data);
    }
  }

  /// Push [data] only when the container is already loaded: it removes values,
  /// so it is no reason to load one. [hold] as in [_send].
  void _clear(Map<String, Object?> data, {bool hold = false}) {
    if (!_loaded) {
      return;
    }

    _push(data);

    if (hold) {
      _hold(data);
    }
  }

  void _ensureLoaded() {
    if (_loaded) {
      return;
    }

    _loaded = true;

    // The bootstrap seeds both page fields with the origin root (below).
    final String originRoot = _onOrigin('/');

    _held
      ..putIfAbsent('page_location', () => originRoot)
      ..putIfAbsent('page_referrer', () => originRoot);

    // A second driver, or a second first use, must not inject twice.
    if (web.document.querySelector('script[src="$_loaderSrc"]') != null) {
      return;
    }

    // 1. The inline script runs on insertion, so `dataLayer`, `gtag` and the
    //    consent default exist before the loader is even requested.
    final web.HTMLScriptElement bootstrap =
        web.document.createElement('script') as web.HTMLScriptElement
          ..setAttribute(_marker, 'bootstrap')
          ..text = _bootstrap;

    web.document.head!.appendChild(bootstrap);

    // 2. The loader comes second, from the first-party gateway.
    final web.HTMLScriptElement loader =
        web.document.createElement('script') as web.HTMLScriptElement
          ..setAttribute(_marker, 'loader')
          ..async = true
          ..src = _loaderSrc;

    web.document.head!.appendChild(loader);
  }

  void _push(Map<String, Object?> data) {
    (globalContext['dataLayer']! as JSObject).callMethod<JSAny?>(
      'push'.toJS,
      data.jsify(),
    );
  }

  void _gtag(String command, String type, Map<String, Object?> settings) {
    globalContext.callMethod<JSAny?>(
      'gtag'.toJS,
      command.toJS,
      type.toJS,
      settings.jsify(),
    );
  }

  String _onOrigin(String path) =>
      '${web.window.location.origin}${path.startsWith('/') ? path : '/$path'}';

  static String _trimSlashes(String path) =>
      path.trim().replaceAll(RegExp(r'^/+|/+$'), '');
}
