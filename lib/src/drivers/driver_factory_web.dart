import 'analytics_driver.dart';
import 'null_driver.dart';

/// Builds the driver for the web, where analytics goes through GTM only and
/// Firebase is never initialised.
///
/// [config] is the resolved `analytics` config map; see
/// `AnalyticsServiceProvider` for its keys. Answers [NullDriver] until the
/// GTM driver lands, which this arm returns once `gtm.container_id` and
/// `gtm.gateway_path` are both set.
AnalyticsDriver createAnalyticsDriver(Map<String, dynamic> config) =>
    const NullDriver();
