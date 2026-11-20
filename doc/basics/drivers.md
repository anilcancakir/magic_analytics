# Drivers

Three drivers sit behind the facade: Google Tag Manager on web, Firebase on iOS and Android, and a null driver when nothing is configured.

- [Quick Reference](#quick-reference)
- [Picking the Driver](#picking-the-driver)
- [Web Driver](#web-driver)
- [Container Setup](#container-setup)
- [Firebase Driver](#firebase-driver)
- [Null Driver](#null-driver)
- [Writing a Driver](#writing-a-driver)
- [Gotchas](#gotchas)
- [Related Documentation](#related-documentation)

<a name="quick-reference"></a>
## Quick Reference

| Platform | Driver | Runs when |
|:---------|:-------|:----------|
| Web | `GtmWebDriver` | `analytics.enabled` is `true` and `gtm.container_id` and `gtm.gateway_path` are both set |
| iOS, Android | `FirebaseDriver` | `analytics.enabled` is `true` and `firebase_options` is a `FirebaseOptions Function()` |
| Anything else, or not configured | `NullDriver` | Always |

A driver only transports. The facade has already validated, scrubbed and gated each call, so a driver re-checks none of it.

<a name="picking-the-driver"></a>
## Picking the Driver

`AnalyticsServiceProvider` reads the `analytics` config map and calls `createAnalyticsDriver`, which is a conditional export: the `dart.library.js_interop` arm is the web build, `dart.library.io` is iOS and Android, and a stub that answers `NullDriver` is the default. The web arm keys on `js_interop` and not on the legacy `dart:html`, which a WebAssembly build lacks. The result is that the Firebase code is never reachable from a web build, so Firebase is never initialised there.

Without `analytics.enabled: true` the provider skips all of this and binds `NullDriver`.

<a name="web-driver"></a>
## Web Driver

`GtmWebDriver` loads a Google Tag Manager container from your first-party gateway path and feeds GA4 through it.

**Lazy load.** Nothing touches the page until the first call that sends something, so a device that opted out never loads the container and never gets a `dataLayer`. Then, in order: an inline script defines `window.dataLayer` and the `gtag` shim, defaults consent (analytics granted, every ad signal denied), pre-seeds the page fields (below) and pushes `gtm.start`; only after that is the loader `<script async src="/<gateway>/?id=<id>">` appended. The shim is real JavaScript on purpose: GTM ignores a consent command pushed as a plain array or object.

**What each call pushes** to the data layer your container's variables read:

| Call | Data layer push |
|:-----|:----------------|
| `screen` | `{event: 'page_view', page_title, page_location, page_referrer}`, the locations built from the origin and the route pattern; the first page's referrer is the origin root, never `null` |
| `track` | `{event: <name>, ...parameters}`, then `{<each parameter key>: <the value the driver holds for it, or null>}`, so the parameters stay with this event (see below) |
| `identify` | `{user_id: <id>}`; `null` on reset |
| `setUserProperties` | `{user_properties: {<name>: <value>}}`, nested |
| `setDefaultParams` | The keys flat; the data layer keeps them for every later push |

The data layer is a merged model, not a queue: a key keeps its value for every later push until something pushes it again. Without the second push after `track`, a `monitor_type` sent with one event would reach every later event whose tag reads that variable, and an event parameter named like a default parameter (`plan` in a `plan_changed` event) would replace the default for good. The driver puts each key back to the value it holds outside events (the user id, the user properties, the last page view's fields or a default parameter), or to `null` when it holds none.

`page_location` is the page's origin plus the route PATTERN, so the real URL, which may carry a token, never leaves. The container's GA4 configuration must set `send_page_view` to `false`, because this driver pushes the page views itself.

**Origin-only pre-seed.** Before `gtm.start`, the bootstrap pushes `{page_location: <origin>/, page_referrer: <origin>/}`. Until the first page view is pushed, a data layer variable bound to `page_location` would be undefined and the Google tag would fall back to the real `document.location`, which can carry a reset token or an invitation path. The seed carries the origin alone, so no path or query is ever read from the address bar.

A set of removals (`reset`, a `null` user id, a `null` property) only pushes when the container is already loaded, so it never loads one. `clientId()` reads the `_ga` cookie and is `null` until the container has set it.

<a name="container-setup"></a>
## Container Setup

The Google tag alone sends none of the driver's events: it only configures the property. The container needs these pieces for an event to reach GA4.

| Piece | Setting |
|:------|:--------|
| Data Layer Variables, version 2 | One each for `page_location`, `page_referrer`, `page_title`, `user_id`, every key you pass to `Analytics.setDefaultParams` (for example `team_plan`) and `user_properties.<name>` for each key you pass to `Analytics.setUserProperties` |
| Event Settings Variable | A Google tag Event Settings Variable that maps `page_location`, `page_referrer`, `page_title` and `user_id` to those variables and lists the default params and user properties; both tags below use it |
| Google tag | The measurement ID, `send_page_view` set to `false`, the Event Settings Variable |
| GA4 Event tag | Event name `{{Event}}`, the Event Settings Variable, and one Event Parameter per event key you want reported |
| Trigger | A Custom Event trigger with event name `.*` and regex matching on, excluding events whose name starts with `gtm.` |
| Consent | Both tags, under Advanced Settings, Consent Settings: "Require additional consent for tag to fire" with `analytics_storage` |

`{{Event}}` is the built-in variable for the `event` key, so one tag reports every `Analytics.track` name and the `page_view` the driver pushes. Sharing the Event Settings Variable between the Google tag and the event tag sets the page fields on every event, not only on the first.

Requiring `analytics_storage` on both tags matters for opt-out: without it, a Google tag whose consent is denied still sends cookieless pings. With it, an opted-out device sends nothing after the driver's consent update.

<a name="firebase-driver"></a>
## Firebase Driver

`FirebaseDriver` sends through `firebase_analytics`. The factory is synchronous, so the first call initialises Firebase (when your app has not), sets consent and enables collection, once.

- Consent on every start: analytics storage granted, `ad_storage`, `ad_user_data` and `ad_personalization` denied. Nothing flips the ad signals.
- Collection is switched on at first use unless the device opted out. The native keys ship it off, so nothing is collected before then.
- A page view is `screen_view` with the route pattern as the screen name and class; the location and referrer are not Firebase parameters and are dropped.
- Default parameters go through `setDefaultEventParameters`, which takes the whole map.
- `reset()` nulls the user id, every user property and the default parameters. It never calls `resetAnalyticsData`, which would rotate the app instance id.

<a name="null-driver"></a>
## Null Driver

`NullDriver` completes every call and sends nothing, and `clientId()` answers `null`. It keeps the package inert until the host sets its IDs, and it is what a platform without a transport gets.

<a name="writing-a-driver"></a>
## Writing a Driver

A driver implements `AnalyticsDriver`. A driver may throw: the manager catches and logs. `setDefaultParams` receives only the keys to change, and a `null` value removes that key. `reset()` runs after the manager has already nulled the identity through the other methods, so it clears only what those cannot reach, and it must not rotate the client id.

```dart
import 'package:magic_analytics/magic_analytics.dart';

/// Records each event and page view, as a starting point for a custom transport.
class LogDriver implements AnalyticsDriver {
  final List<String> lines = <String>[];

  @override
  Future<void> logEvent(String name, Map<String, Object> parameters) async {
    lines.add('$name $parameters');
  }

  @override
  Future<void> logScreen({
    required String name,
    String? location,
    String? referrer,
  }) async {
    lines.add('screen $name');
  }

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
```

Bind a manager over it with `app.singleton('analytics', () => AnalyticsManager(LogDriver()))` in your own provider, instead of registering `AnalyticsServiceProvider`.

<a name="gotchas"></a>
## Gotchas

| Mistake | Fix |
|:--------|:----|
| A container served from `googletagmanager.com` | Set `gtm.gateway_path`; without it the web driver is the null driver |
| Leaving `send_page_view` on in the GA4 configuration | Set it to `false`; the driver pushes each page view and a second source double counts |
| A container with only the Google tag | Add the GA4 Event tag on a Custom Event trigger, or no custom event reaches GA4 |
| Tags without `analytics_storage` required | Require it on both, or an opted-out device still sends cookieless pings |
| Initialising Firebase on web | Never; leave `firebase_options` `null` there |
| Expecting the web driver to send before the first event | It loads lazily, so the network tab is empty until then |
| `firebase_options` set to a value, not a function | It must be `() => DefaultFirebaseOptions.currentPlatform` |

<a name="related-documentation"></a>
## Related Documentation

- [Facade and Provider](facade-and-provider.md): the calls a driver receives.
- [Consent and Opt-Out](consent-and-opt-out.md): how each driver stops collecting.
- [Installation](../getting-started/installation.md): the gateway and the native keys.
