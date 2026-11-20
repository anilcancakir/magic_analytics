import 'analytics_driver.dart';
import 'gtm_web_driver.dart';
import 'null_driver.dart';

/// Builds the driver for the web, where analytics goes through GTM only and
/// Firebase is never initialised.
///
/// [config] is the resolved `analytics` config map; see
/// `AnalyticsServiceProvider` for its keys. Answers a [GtmWebDriver] once
/// `gtm.container_id` and `gtm.gateway_path` are both set, [NullDriver]
/// otherwise, so a container is never loaded from Google's own host.
AnalyticsDriver createAnalyticsDriver(Map<String, dynamic> config) =>
    GtmWebDriver.fromConfig(config) ?? const NullDriver();
