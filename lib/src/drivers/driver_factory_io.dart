import 'analytics_driver.dart';
import 'null_driver.dart';

/// Builds the driver for iOS and Android, where analytics goes through
/// Firebase.
///
/// [config] is the resolved `analytics` config map; see
/// `AnalyticsServiceProvider` for its keys. Answers [NullDriver] until the
/// Firebase driver lands, which this arm returns once `firebase_options` is
/// set (a `FirebaseOptions Function()`, cast here and nowhere else).
AnalyticsDriver createAnalyticsDriver(Map<String, dynamic> config) =>
    const NullDriver();
