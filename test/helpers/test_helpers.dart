import 'package:magic/magic.dart';
import 'package:magic_analytics/magic_analytics.dart';

/// A minimal authenticatable model, keyed by a string id as uptizm's UUIDs are.
class TestUser extends Model with Authenticatable {
  @override
  String get table => 'users';

  @override
  String get resource => 'users';
}

/// A [TestUser] whose primary key is [id].
TestUser testUser(String id) =>
    TestUser()..setRawAttributes({'id': id}, sync: true);

/// Clears the container and the config, the per-test mount discipline.
void resetMagic() {
  MagicApp.reset();
  Magic.flush();
}

/// Lets the analytics send queue drain: the manager hands every call to the
/// driver on a later microtask, so a call fired without `await` (an auth
/// listener, a navigator observer) lands only after this.
Future<void> drainAnalytics() => Future<void>.delayed(Duration.zero);

/// A driver whose every transport call fails, to prove the facade boundary
/// catches and logs instead of throwing into UI flow.
class ThrowingDriver implements AnalyticsDriver {
  @override
  Future<void> logEvent(String name, Map<String, Object> parameters) => _fail();

  @override
  Future<void> logScreen({
    required String name,
    String? location,
    String? referrer,
  }) => _fail();

  @override
  Future<void> setUserId(String? userId) => _fail();

  @override
  Future<void> setUserProperty(String name, String? value) => _fail();

  @override
  Future<void> setDefaultParams(Map<String, Object?> parameters) => _fail();

  @override
  Future<void> setOptOut(bool optedOut) => _fail();

  @override
  Future<String?> clientId() => throw StateError('transport down');

  @override
  Future<void> reset() => _fail();

  Future<void> _fail() async => throw StateError('transport down');
}
