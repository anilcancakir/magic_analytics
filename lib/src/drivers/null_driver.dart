import 'analytics_driver.dart';

/// The driver used when analytics is disabled or no ID is configured: every
/// call completes without sending anything, which keeps the package inert
/// until the host sets its IDs.
class NullDriver implements AnalyticsDriver {
  /// Creates the inert driver.
  const NullDriver();

  @override
  Future<void> logEvent(String name, Map<String, Object> parameters) async {}

  @override
  Future<void> logScreen({
    required String name,
    String? location,
    String? referrer,
  }) async {}

  @override
  Future<void> setUserId(String? userId) async {}

  @override
  Future<void> setUserProperty(String name, String? value) async {}

  @override
  Future<void> setDefaultParams(Map<String, Object?> parameters) async {}

  @override
  Future<void> setOptOut(bool optedOut) async {}

  @override
  Future<String?> clientId() async => null;

  @override
  Future<void> reset() async {}
}
