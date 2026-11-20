import 'package:firebase_core/firebase_core.dart';

import 'analytics_driver.dart';
import 'firebase_driver.dart';
import 'null_driver.dart';

/// Builds the driver for iOS and Android, where analytics goes through
/// Firebase.
///
/// [config] is the resolved `analytics` config map; see
/// `AnalyticsServiceProvider` for its keys. Answers [FirebaseDriver] when
/// `firebase_options` is a `FirebaseOptions Function()` (typically
/// `() => DefaultFirebaseOptions.currentPlatform`) and [NullDriver] otherwise.
AnalyticsDriver createAnalyticsDriver(Map<String, dynamic> config) {
  final Object? options = config['firebase_options'];

  if (options is! FirebaseOptions Function()) {
    return const NullDriver();
  }

  return FirebaseDriver(options: options);
}
