import '../drivers/analytics_driver.dart';

/// What kind of driver call a [RecordedAnalyticsCall] captured.
enum RecordedCallKind {
  /// `logEvent`.
  event,

  /// `logScreen`.
  screen,

  /// `setUserId`.
  userId,

  /// `setUserProperty`.
  userProperty,

  /// `setDefaultParams`.
  defaultParams,

  /// `setOptOut`.
  optOut,

  /// `reset`.
  reset,
}

/// One driver call captured by [FakeAnalytics], with the identity the
/// transport held when it arrived.
class RecordedAnalyticsCall {
  /// Creates a record; the maps are copied so later calls cannot move it.
  RecordedAnalyticsCall({
    required this.kind,
    required this.name,
    required Map<String, Object?> parameters,
    required this.userId,
    required Map<String, String> userProperties,
    required Map<String, Object> defaultParams,
  }) : parameters = Map<String, Object?>.unmodifiable(parameters),
       userProperties = Map<String, String>.unmodifiable(userProperties),
       defaultParams = Map<String, Object>.unmodifiable(defaultParams);

  /// The kind of call.
  final RecordedCallKind kind;

  /// The event name, page name or user property name; null for the others.
  final String? name;

  /// What the call carried: the event parameters; `location` and `referrer`
  /// for a screen; `user_id`; the property `value`; the default parameter
  /// update; `opted_out`. Empty for a reset.
  final Map<String, Object?> parameters;

  /// The user id the transport held when the call arrived.
  final String? userId;

  /// The user properties the transport held when the call arrived.
  final Map<String, String> userProperties;

  /// The default parameters the transport held when the call arrived.
  final Map<String, Object> defaultParams;

  @override
  String toString() =>
      '${kind.name}(name: $name, parameters: $parameters, userId: $userId, '
      'userProperties: $userProperties, defaultParams: $defaultParams)';
}

/// A recording [AnalyticsDriver], bound by `Analytics.fake()`.
///
/// It sits behind the real manager, so it records only what passed
/// validation, scrubbing and the opt-out gate, in the order the manager sent
/// it. It also keeps the identity a real transport would hold ([userId],
/// [userProperties], [defaultParams]) and stamps it on every record.
class FakeAnalytics implements AnalyticsDriver {
  /// Every call, in arrival order. Mutable so a test can clear it between
  /// phases.
  final List<RecordedAnalyticsCall> calls = <RecordedAnalyticsCall>[];

  /// The user id currently held.
  String? userId;

  /// The user properties currently held.
  final Map<String, String> userProperties = <String, String>{};

  /// The default parameters currently held.
  final Map<String, Object> defaultParams = <String, Object>{};

  /// Whether the device is currently opted out.
  bool optedOut = false;

  /// What [clientId] answers.
  String? clientIdValue;

  /// The recorded events.
  List<RecordedAnalyticsCall> get events => _ofKind(RecordedCallKind.event);

  /// The recorded page views.
  List<RecordedAnalyticsCall> get screens => _ofKind(RecordedCallKind.screen);

  @override
  Future<void> logEvent(String name, Map<String, Object> parameters) async {
    _record(RecordedCallKind.event, name, parameters);
  }

  @override
  Future<void> logScreen({
    required String name,
    String? location,
    String? referrer,
  }) async {
    _record(RecordedCallKind.screen, name, <String, Object?>{
      'location': location,
      'referrer': referrer,
    });
  }

  @override
  Future<void> setUserId(String? userId) async {
    this.userId = userId;
    _record(RecordedCallKind.userId, null, <String, Object?>{
      'user_id': userId,
    });
  }

  @override
  Future<void> setUserProperty(String name, String? value) async {
    if (value == null) {
      userProperties.remove(name);
    } else {
      userProperties[name] = value;
    }

    _record(RecordedCallKind.userProperty, name, <String, Object?>{
      'value': value,
    });
  }

  @override
  Future<void> setDefaultParams(Map<String, Object?> parameters) async {
    parameters.forEach((key, value) {
      if (value == null) {
        defaultParams.remove(key);
      } else {
        defaultParams[key] = value;
      }
    });

    _record(RecordedCallKind.defaultParams, null, parameters);
  }

  @override
  Future<void> setOptOut(bool optedOut) async {
    this.optedOut = optedOut;
    _record(RecordedCallKind.optOut, null, <String, Object?>{
      'opted_out': optedOut,
    });
  }

  @override
  Future<String?> clientId() async => clientIdValue;

  @override
  Future<void> reset() async {
    _record(RecordedCallKind.reset, null, const <String, Object?>{});
  }

  /// Throws [AssertionError] unless an event named [name] was sent.
  void assertTracked(String name) {
    if (!events.any((call) => call.name == name)) {
      throw AssertionError(
        'Expected the event "$name" to be sent; it was not.',
      );
    }
  }

  /// Throws [AssertionError] if an event named [name] was sent.
  void assertNotTracked(String name) {
    if (events.any((call) => call.name == name)) {
      throw AssertionError('Expected the event "$name" not to be sent.');
    }
  }

  /// Throws [AssertionError] if any call reached the driver.
  void assertNothingSent() {
    if (calls.isNotEmpty) {
      throw AssertionError('Expected no analytics call, got: $calls');
    }
  }

  List<RecordedAnalyticsCall> _ofKind(RecordedCallKind kind) =>
      calls.where((call) => call.kind == kind).toList();

  void _record(
    RecordedCallKind kind,
    String? name,
    Map<String, Object?> parameters,
  ) {
    calls.add(
      RecordedAnalyticsCall(
        kind: kind,
        name: name,
        parameters: parameters,
        userId: userId,
        userProperties: userProperties,
        defaultParams: defaultParams,
      ),
    );
  }
}
