import 'analytics_driver.dart';
import 'null_driver.dart';

/// Builds the driver for a platform with neither `dart:js_interop` nor
/// `dart:io`; no real Flutter target lands here, so it is always inert.
///
/// [config] is the resolved `analytics` config map; see
/// `AnalyticsServiceProvider` for its keys.
AnalyticsDriver createAnalyticsDriver(Map<String, dynamic> config) =>
    const NullDriver();
