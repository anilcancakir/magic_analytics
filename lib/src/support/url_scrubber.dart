import 'package:flutter/foundation.dart' show listEquals;
import 'package:magic/magic.dart';

/// A registered route with at least one `*token*` param: the pattern that
/// finds it in a text and the indexes of the segments to mask.
typedef _TokenRoute = ({RegExp shape, List<int> tokenSegments});

/// Masks secrets in a URL, or in any text, before it is sent to analytics.
///
/// A magic route like `/invitations/:token/accept` puts a credential in the
/// PATH, and a reset link puts one, and the account's email, in the QUERY.
/// Every page location, referrer, title and string event parameter passes
/// through [scrub] before it leaves the device.
///
/// THREE RULES, applied in this order:
///
/// 1. QUERY VALUES. A `?key=value`, `&key=value` or `#key=value` pair whose
///    key contains `token`, `password`, `secret`, `signature`, `credential`,
///    `api_key`, `email` or `code` (any case) keeps its key and loses its
///    value.
/// 2. ROUTE-BOUND SEGMENTS. A path segment sitting where a registered magic
///    route has a param whose name contains `token` is masked. The routes are
///    read from `MagicRouter.instance.allRoutes` at scrub time, so a route
///    inside a layout group, or one added after boot, is covered too.
/// 3. EMAIL ADDRESSES. Anything shaped like an email address, raw or with a
///    percent-encoded `@`, is masked wherever it appears.
///
/// A masked value becomes [filtered] rather than disappearing, so a report
/// still shows that the URL carried a secret and where. Text with nothing to
/// mask comes back unchanged, character for character.
///
/// Rules 1 and 2 mirror magic_sentry's `SentryTokenScrubber`, copied rather
/// than imported so this package does not depend on Sentry.
abstract final class UrlScrubber {
  /// What a masked value is replaced with.
  static const String filtered = '[Filtered]';

  /// A pair whose KEY names a secret. The value stops at `&`, `#` or
  /// whitespace, so a URL inside a longer text loses only the value.
  static final RegExp _sensitiveQueryPair = RegExp(
    r'([?&#])([^=&#\s]*(?:token|password|secret|signature|credential|api_key'
    r'|email|code)[^=&#\s]*)=([^&#\s]*)',
    caseSensitive: false,
  );

  /// An email address, with a raw `@` or a percent-encoded one (`%40`).
  static final RegExp _emailAddress = RegExp(
    r'[A-Za-z0-9._%+-]+(?:@|%40)[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+',
  );

  static List<String> _compiledPaths = <String>[];

  static List<_TokenRoute> _compiledRoutes = <_TokenRoute>[];

  /// [text] with every secret the three rules find replaced by [filtered].
  static String scrub(String text) =>
      _maskEmails(_maskRouteTokens(_maskQueryValues(text)));

  static String _maskQueryValues(String text) {
    return text.replaceAllMapped(
      _sensitiveQueryPair,
      (Match match) => '${match[1]}${match[2]}=$filtered',
    );
  }

  static String _maskEmails(String text) =>
      text.replaceAll(_emailAddress, filtered);

  /// Masks the segment of every registered route param named `*token*`.
  ///
  /// A route matches only as a whole path, starting at the beginning of the
  /// text, after whitespace or right after `scheme://host` (or `scheme://host/#`
  /// for a hash-routed URL), so `/monitors/:token` never touches
  /// `/api/monitors/x`.
  static String _maskRouteTokens(String text) {
    String masked = text;

    for (final _TokenRoute route in _tokenRoutes()) {
      masked = masked.replaceAllMapped(route.shape, (Match match) {
        final List<String> segments = match[2]!.split('/');

        for (final int index in route.tokenSegments) {
          segments[index] = filtered;
        }

        return '${match[1]}${segments.join('/')}';
      });
    }

    return masked;
  }

  /// The compiled token routes, rebuilt only when the registered paths change.
  ///
  /// Compared by path and not by count: a route replaced by another, or the
  /// router reset and re-registered, keeps the same count.
  static List<_TokenRoute> _tokenRoutes() {
    // `allRoutes`, not `routes`: the latter holds only top-level routes, and
    // magic_starter keeps `/invitations/:token/accept` inside a layout group.
    final List<String> paths = <String>[
      for (final RouteDefinition route in MagicRouter.instance.allRoutes)
        route.fullPath,
    ];

    if (listEquals(paths, _compiledPaths)) {
      return _compiledRoutes;
    }

    _compiledPaths = paths;
    _compiledRoutes = <_TokenRoute>[
      for (final String path in paths)
        if (path.split('/').any(_isTokenParam)) _compileRoute(path),
    ];

    return _compiledRoutes;
  }

  static _TokenRoute _compileRoute(String path) {
    final List<String> pattern = path.split('/');

    return (
      shape: RegExp(
        r'(^|\s|://[^/\s]*(?:/#)?)'
        '(${pattern.map(_segmentShape).join('/')}'
        r'/?)(?=$|[\s?#])',
      ),
      tokenSegments: <int>[
        for (int i = 0; i < pattern.length; i++)
          if (_isTokenParam(pattern[i])) i,
      ],
    );
  }

  static bool _isTokenParam(String segment) =>
      segment.startsWith(':') && segment.toLowerCase().contains('token');

  static String _segmentShape(String segment) =>
      segment.startsWith(':') ? r'[^/\s?#]+' : RegExp.escape(segment);
}
