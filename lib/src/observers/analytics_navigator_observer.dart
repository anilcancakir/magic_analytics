import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../facades/analytics.dart';

/// Reports a page view each time a named page comes to the top.
///
/// magic names every page by its route name or its path PATTERN
/// (`/monitors/:id`, never `/monitors/42`), so the page view carries that
/// name as its title and the pattern as its location: no id, token or email
/// in either, and every monitor's page counts as one page. A page without a
/// name (a dialog, a bottom sheet) is not a page view.
///
/// Registered on the root navigator by `AnalyticsServiceProvider`; go_router
/// forwards in-shell navigation to root observers, so shell pages are seen.
class AnalyticsNavigatorObserver extends NavigatorObserver {
  /// The location of the last page reported, the next one's referrer.
  String? _lastLocation;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _report(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute != null) {
      _report(newRoute);
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // Closing a dialog reveals the same page, which is not a new view.
    if (route.settings.name == null || previousRoute == null) {
      return;
    }

    _report(previousRoute);
  }

  void _report(Route<dynamic> route) {
    final String? name = route.settings.name;

    if (name == null) {
      return;
    }

    final String? location = _locationFor(name);

    Analytics.screen(name, location: location, referrer: _lastLocation);
    _lastLocation = location;
  }

  /// The path pattern for the page [name]: the name itself when it is a
  /// path, else the pattern of the route registered under that name.
  String? _locationFor(String name) {
    if (name.startsWith('/')) {
      return name;
    }

    for (final RouteDefinition route in MagicRouter.instance.allRoutes) {
      if (route.routeName == name) {
        return route.fullPath;
      }
    }

    return null;
  }
}
