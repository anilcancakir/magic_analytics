@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic_analytics/src/drivers/driver_factory_web.dart';
import 'package:magic_analytics/src/drivers/gtm_web_driver.dart';
import 'package:magic_analytics/src/drivers/null_driver.dart';
import 'package:web/web.dart' as web;

const String _containerId = 'GTM-ABC123';
const String _loaderSrc = '/f86e269b/?id=GTM-ABC123';
const String _scriptSelector = 'script[data-magic-analytics]';

GtmWebDriver _driver([String gatewayPath = '/f86e269b']) =>
    GtmWebDriver(containerId: _containerId, gatewayPath: gatewayPath);

/// The page's `dataLayer` entries, empty when the page has none.
List<JSObject> _dataLayer() {
  final JSAny? layer = globalContext['dataLayer'];

  if (layer == null) {
    return <JSObject>[];
  }

  return (layer as JSArray<JSAny?>).toDart.cast<JSObject>();
}

/// `Object.prototype.toString.call(value)`, which names an `arguments` object.
String _tagOf(JSObject value) {
  final JSObject toString = (globalContext['Object']! as JSObject)
      .getProperty<JSObject>('prototype'.toJS)
      .getProperty<JSObject>('toString'.toJS);

  return toString.callMethod<JSString>('call'.toJS, value).toDart;
}

String? _string(JSObject object, String key) =>
    (object[key] as JSString?)?.toDart;

JSObject _object(JSObject object, String key) => object[key]! as JSObject;

/// The last `dataLayer` entry that carries [key].
JSObject _lastWith(String key) =>
    _dataLayer().lastWhere((entry) => entry.has(key));

List<web.Element> _scripts() {
  final web.NodeList nodes = web.document.querySelectorAll(_scriptSelector);

  return <web.Element>[
    for (int index = 0; index < nodes.length; index++)
      nodes.item(index)! as web.Element,
  ];
}

void _removeInjected() {
  for (final web.Element script in _scripts()) {
    script.remove();
  }

  globalContext.delete('dataLayer'.toJS);
  globalContext.delete('gtag'.toJS);
}

void main() {
  setUp(_removeInjected);

  tearDown(() {
    _removeInjected();
    web.document.cookie = '_ga=; expires=Thu, 01 Jan 1970 00:00:00 GMT; path=/';
  });

  group('first send', () {
    test(
      'defaults consent with an arguments object before the loader',
      () async {
        await _driver().logEvent('monitor_created', <String, Object>{});

        final List<JSObject> layer = _dataLayer();
        final JSObject consent = layer.first;

        expect(_tagOf(consent), '[object Arguments]');
        expect(_string(consent, '0'), 'consent');
        expect(_string(consent, '1'), 'default');

        final JSObject defaults = _object(consent, '2');

        expect(_string(defaults, 'analytics_storage'), 'granted');
        expect(_string(defaults, 'ad_storage'), 'denied');
        expect(_string(defaults, 'ad_user_data'), 'denied');
        expect(_string(defaults, 'ad_personalization'), 'denied');
        expect(_string(layer[2], 'event'), 'gtm.js');

        final List<web.Element> scripts = _scripts();

        expect(scripts, hasLength(2));
        expect(scripts.first.getAttribute('src'), isNull);
        expect(scripts.last.getAttribute('src'), _loaderSrc);
        expect(
          scripts.first.compareDocumentPosition(scripts.last) &
              web.Node.DOCUMENT_POSITION_FOLLOWING,
          isNonZero,
        );
      },
    );

    for (final String path in <String>['f86e269b', '/f86e269b', '/f86e269b/']) {
      test('normalises the gateway path "$path"', () async {
        await _driver(path).logEvent('monitor_created', <String, Object>{});

        expect(_scripts().last.getAttribute('src'), _loaderSrc);
      });
    }

    test(
      'pre-seeds origin-only page fields before the container initialises',
      () async {
        final String originalPath =
            '${web.window.location.pathname}${web.window.location.search}';

        addTearDown(
          () => web.window.history.replaceState(null, '', originalPath),
        );
        web.window.history.replaceState(
          null,
          '',
          '/reset-password/secret-path-token?token=abc123&email=a%40b.co',
        );

        await _driver().logEvent('monitor_created', <String, Object>{});

        final List<JSObject> layer = _dataLayer();
        final int seedIndex = layer.indexWhere(
          (entry) =>
              _tagOf(entry) != '[object Arguments]' &&
              entry.has('page_location'),
        );
        final int loaderIndex = layer.indexWhere(
          (entry) => _string(entry, 'event') == 'gtm.js',
        );
        final String origin = web.window.location.origin;

        expect(seedIndex, isNonNegative);
        expect(seedIndex, lessThan(loaderIndex));
        expect(layer[seedIndex].has('event'), isFalse);
        expect(_string(layer[seedIndex], 'page_location'), '$origin/');
        expect(_string(layer[seedIndex], 'page_referrer'), '$origin/');

        for (final String key in <String>['page_location', 'page_referrer']) {
          final String value = _string(layer[seedIndex], key)!;

          expect(value, isNot(contains('secret-path-token')));
          expect(value, isNot(contains('token=')));
          expect(value, isNot(contains('@')));
        }
      },
    );

    test('loads once however many drivers send', () async {
      await _driver().logEvent('first', <String, Object>{});
      await _driver().logEvent('second', <String, Object>{});

      expect(_scripts(), hasLength(2));
      expect(
        _dataLayer().where((entry) => _string(entry, 'event') == 'gtm.js'),
        hasLength(1),
      );
    });

    test('is lazy: building the driver loads nothing', () {
      _driver();

      expect(_scripts(), isEmpty);
      expect(globalContext.has('dataLayer'), isFalse);
    });
  });

  group('opted out', () {
    test('loads nothing and creates no dataLayer', () async {
      final GtmWebDriver driver = _driver();

      await driver.setOptOut(true);
      await driver.setUserId(null);
      await driver.reset();
      await driver.clientId();

      expect(_scripts(), isEmpty);
      expect(globalContext.has('dataLayer'), isFalse);
    });

    test('stops sending, and denies analytics storage once loaded', () async {
      final GtmWebDriver driver = _driver();

      await driver.logEvent('monitor_created', <String, Object>{});
      await driver.setOptOut(true);

      final JSObject update = _dataLayer().last;

      expect(_tagOf(update), '[object Arguments]');
      expect(_string(update, '1'), 'update');
      expect(_string(_object(update, '2'), 'analytics_storage'), 'denied');

      final int length = _dataLayer().length;

      await driver.logEvent('monitor_deleted', <String, Object>{});

      expect(_dataLayer(), hasLength(length));

      await driver.setOptOut(false);
      await driver.logEvent('monitor_deleted', <String, Object>{});

      final JSObject granted = _dataLayer().reversed.firstWhere(
        (entry) => _string(entry, '1') == 'update',
      );

      expect(_string(_object(granted, '2'), 'analytics_storage'), 'granted');
      expect(_string(_dataLayer().last, 'event'), 'monitor_deleted');
    });
  });

  group('pushes', () {
    test('logEvent pushes the event with its parameters', () async {
      await _driver().logEvent('monitor_created', <String, Object>{
        'monitor_type': 'http',
        'count': 2,
      });

      final JSObject entry = _dataLayer().last;

      expect(_string(entry, 'event'), 'monitor_created');
      expect(_string(entry, 'monitor_type'), 'http');
      expect((entry['count']! as JSNumber).toDartInt, 2);
    });

    test(
      'logScreen reports the route pattern, never the real location',
      () async {
        await _driver().logScreen(
          name: '/monitors/:id',
          location: '/monitors/:id',
          referrer: '/monitors',
        );

        final JSObject entry = _dataLayer().last;
        final String origin = web.window.location.origin;

        expect(_string(entry, 'event'), 'page_view');
        expect(_string(entry, 'page_title'), '/monitors/:id');
        expect(_string(entry, 'page_location'), '$origin/monitors/:id');
        expect(_string(entry, 'page_referrer'), '$origin/monitors');
      },
    );

    test('logScreen falls back to the origin root for both fields', () async {
      await _driver().logScreen(name: 'home');

      final JSObject entry = _dataLayer().last;
      final String origin = web.window.location.origin;

      expect(_string(entry, 'page_location'), '$origin/');
      expect(_string(entry, 'page_referrer'), '$origin/');
    });

    test('setUserId and setUserProperty push user-level keys', () async {
      final GtmWebDriver driver = _driver();

      await driver.setUserId('9b1f0a7e');
      await driver.setUserProperty('locale', 'tr');

      expect(_string(_lastWith('user_id'), 'user_id'), '9b1f0a7e');
      expect(
        _string(
          _object(_lastWith('user_properties'), 'user_properties'),
          'locale',
        ),
        'tr',
      );
    });

    test('setDefaultParams pushes the merged keys, null included', () async {
      await _driver().setDefaultParams(<String, Object?>{
        'team_plan': 'pro',
        'team_size': null,
      });

      final JSObject entry = _dataLayer().last;

      expect(_string(entry, 'team_plan'), 'pro');
      expect(entry.has('team_size'), isTrue);
      expect(entry['team_size'], isNull);
    });

    test('reset pushes user_id null and nulls every key it pushed', () async {
      final GtmWebDriver driver = _driver();

      await driver.setUserId('9b1f0a7e');
      await driver.setUserProperty('locale', 'tr');
      await driver.setDefaultParams(<String, Object?>{'team_plan': 'pro'});
      await driver.reset();

      final JSObject entry = _dataLayer().last;

      expect(entry.has('user_id'), isTrue);
      expect(entry['user_id'], isNull);
      expect(entry['team_plan'], isNull);
      expect(entry.has('team_plan'), isTrue);

      final JSObject properties = _object(entry, 'user_properties');

      expect(properties.has('locale'), isTrue);
      expect(properties['locale'], isNull);
    });
  });

  group('clientId', () {
    test('reads it from the _ga cookie', () async {
      web.document.cookie = '_ga=GA1.1.123.456; path=/';

      expect(await _driver().clientId(), '123.456');
    });

    test('is null without the cookie, and does not create it', () async {
      expect(await _driver().clientId(), isNull);
      expect(web.document.cookie, isNot(contains('_ga=')));
    });
  });

  group('createAnalyticsDriver', () {
    test('builds the GTM driver from both ids', () {
      final driver = createAnalyticsDriver(<String, dynamic>{
        'gtm': <String, dynamic>{
          'container_id': _containerId,
          'gateway_path': '/f86e269b',
        },
      });

      expect(driver, isA<GtmWebDriver>());
    });

    test(
      'answers NullDriver and loads nothing without a gateway path',
      () async {
        final driver = createAnalyticsDriver(<String, dynamic>{
          'gtm': <String, dynamic>{'container_id': _containerId},
        });

        await driver.logEvent('monitor_created', <String, Object>{});

        expect(driver, isA<NullDriver>());
        expect(_scripts(), isEmpty);
        expect(globalContext.has('dataLayer'), isFalse);
      },
    );

    test('answers NullDriver for an empty or missing id', () {
      for (final Map<String, dynamic> config in <Map<String, dynamic>>[
        <String, dynamic>{},
        <String, dynamic>{
          'gtm': <String, dynamic>{'container_id': '', 'gateway_path': '/x'},
        },
        <String, dynamic>{
          'gtm': <String, dynamic>{
            'container_id': 'GTM-1',
            'gateway_path': '/',
          },
        },
      ]) {
        expect(createAnalyticsDriver(config), isA<NullDriver>());
      }
    });
  });
}
