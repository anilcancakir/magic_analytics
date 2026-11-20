/// The transport behind the `Analytics` facade: GTM on web, Firebase on iOS
/// and Android, `NullDriver` when nothing is configured.
///
/// A driver only TRANSPORTS. The facade has already validated every name and
/// value against the GA4 limits, scrubbed emails and tokens out of every
/// string, applied the opt-out gate and kept the bookkeeping `reset()` needs,
/// so a driver re-checks none of it. The facade also serialises calls, so a
/// driver sees them in the order the app made them and never two at once.
///
/// A driver may throw: the facade catches at its boundary and logs through
/// magic's `Log`, so an error never reaches UI flow.
abstract interface class AnalyticsDriver {
  /// Send the event [name] with [parameters].
  ///
  /// The default parameters set through [setDefaultParams] are NOT merged into
  /// [parameters]; the driver applies them as its transport does (Firebase
  /// `setDefaultEventParameters`, a GTM `dataLayer` set).
  Future<void> logEvent(String name, Map<String, Object> parameters);

  /// Send a page view (GA4 `page_view`, Firebase `screen_view`).
  ///
  /// [name] is the page name and title, the route pattern or route name magic
  /// gives the page (`/monitors/:id`, `monitors.show`). [location] is the
  /// page's path pattern and [referrer] the previous page's, both already
  /// scrubbed and either null when unknown. A web driver may report the real
  /// browser location instead, provided it runs it through `UrlScrubber`.
  Future<void> logScreen({
    required String name,
    String? location,
    String? referrer,
  });

  /// Set the GA4 `user_id`; null clears it.
  Future<void> setUserId(String? userId);

  /// Set the user property [name] to [value]; null clears it.
  Future<void> setUserProperty(String name, String? value);

  /// Merge [parameters] into the parameters sent with every later event.
  ///
  /// A null value removes that key; a key absent from [parameters] keeps its
  /// current value. The facade sends a null for every key it wants gone, so a
  /// driver never has to remember which keys it was given.
  Future<void> setDefaultParams(Map<String, Object?> parameters);

  /// Stop ([optedOut] true) or resume collection on this device.
  Future<void> setOptOut(bool optedOut);

  /// The GA4 client id (Firebase app instance id), or null when the transport
  /// has none yet.
  Future<String?> clientId();

  /// The user signed out.
  ///
  /// Called after the facade has already nulled the user id, every user
  /// property and every default parameter through the methods above, so this
  /// clears only what those cannot reach (a transport-side queue, a cached
  /// identity). It must NOT rotate the client id: the device stays the same.
  Future<void> reset();
}
