# Facade and Provider

`Analytics` is the one static entry point for events, page views, identity and defaults, and `AnalyticsServiceProvider` binds it and wires the router and the auth state.

- [Quick Reference](#quick-reference)
- [Events and Parameters](#events-and-parameters)
- [Identity](#identity)
- [GA4 Limits](#ga4-limits)
- [Order and Failure](#order-and-failure)
- [What the Provider Wires](#what-the-provider-wires)
- [Page Views](#page-views)
- [Gotchas](#gotchas)
- [Related Documentation](#related-documentation)

<a name="quick-reference"></a>
## Quick Reference

```dart
import 'package:magic_analytics/magic_analytics.dart';

Future<void> afterSignIn(String userUuid, String teamPlan) async {
  await Analytics.identify(userUuid);
  await Analytics.setUserProperties({'locale': 'en'});
  await Analytics.setDefaultParams({'team_plan': teamPlan});
  await Analytics.track('monitor_created', {'monitor_type': 'http'});
}
```

| Call | Does |
|:-----|:-----|
| `Analytics.track(name, [parameters])` | Sends the event `name` with string or number parameters |
| `Analytics.screen(name, {location, referrer})` | Sends a page view; the observer calls it for you |
| `Analytics.identify(userId)` | Sets the GA4 user id |
| `Analytics.setUserProperties(properties)` | Sets user-level properties; a `null` value clears one |
| `Analytics.setDefaultParams(parameters)` | Replaces the parameters sent with every event; `null` clears them |
| `Analytics.setOptOut(optedOut)` | Stops or resumes collection on this device |
| `Analytics.isOptedOut` | Whether this device has opted out |
| `Analytics.reset()` | Forgets the signed-in user |
| `Analytics.clientId()` | The GA4 client id, or `null` |

Every call returns a future that never fails: await it in a test, ignore it in app code.

<a name="events-and-parameters"></a>
## Events and Parameters

A parameter value is a string or a number. A string passes through the [URL scrubber](../guides/url-scrubbing.md) first, so an email address or a token inside it leaves the device masked. The limits below apply to what is actually sent.

`setDefaultParams` replaces the whole set: a key left out of the new map is removed. This is where team facts go (a plan, a team size). Each event carries the defaults, and they count toward the 25 parameters an event may carry.

<a name="identity"></a>
## Identity

`identify` takes the user's opaque id, a UUID. It refuses an empty id, one longer than 256 characters and anything the scrubber would mask, so an email address is never an id.

`setUserProperties` is for facts about the USER, not the team: a name is at most 24 characters and a value at most 36. Team facts belong in `setDefaultParams`, so a team switch replaces them instead of leaving the old team on the user.

`reset()` nulls the user id, every user property set since the last reset and every default parameter, then lets the driver clear what is left. It never rotates the client id: the device stays the same across a sign-out. It runs on an opted-out device too.

<a name="ga4-limits"></a>
## GA4 Limits

| Limit | Value |
|:------|:------|
| Event name, parameter name, default parameter name | 40 characters, letters, digits and underscores, starting with a letter |
| Reserved prefixes | `ga_`, `google_`, `firebase_` |
| Parameters per event, defaults included | 25 |
| String parameter value | 100 characters, measured after scrubbing |
| User property name | 24 characters |
| User property value | 36 characters |
| User id | 256 characters |

A call that breaks a limit fails an `assert` in debug, so a test or a debug run stops at the call site. In release the call is dropped and the reason is logged through Magic's `Log` (or `debugPrint` when none is bound). Nothing invalid reaches a driver.

<a name="order-and-failure"></a>
## Order and Failure

Driver calls run one at a time, in call order, on a queue inside `AnalyticsManager`. An auth listener cannot await `reset()`, and without the queue the next user's `setDefaultParams` could reach the driver before the previous user's were cleared.

A driver error is caught at the manager, logged and never rethrown, so an analytics call never throws into UI flow. A limit violation is the one deliberate exception, in debug only.

<a name="what-the-provider-wires"></a>
## What the Provider Wires

| Step | Does |
|:-----|:-----|
| `register()` | Binds the `analytics` singleton, an `AnalyticsManager` over the driver `createAnalyticsDriver` picks for the platform, or `NullDriver` unless `analytics.enabled` is `true` |
| `boot()` | Adds `AnalyticsNavigatorObserver` to `MagicRouter`, once |
| `boot()`, with `auth` bound | Calls `Analytics.reset()` when the signed-in user signs out or changes |

The reset follows `Auth.stateNotifier` and compares the user id, so a team switch (same user) keeps the identity: the app sets the new team's default parameters itself. The provider never calls `identify`.

<a name="page-views"></a>
## Page Views

`AnalyticsNavigatorObserver` reports a page view each time a named page comes to the top. Magic names a page by its route name or its path PATTERN, so the title is `/monitors/:id`, never `/monitors/42`, and the location is the pattern too: no id, token or email in either, and every monitor's page counts as one page. A page without a name (a dialog, a bottom sheet) is not a page view, and closing one does not report the page beneath again. The previous page's pattern is the next page's referrer.

<a name="gotchas"></a>
## Gotchas

| Mistake | Fix |
|:--------|:----|
| Putting a team plan in `setUserProperties` | Use `setDefaultParams`; user properties are user-level |
| Calling `setDefaultParams` with only the new key | It replaces the set; pass every default you want kept |
| Passing an email to `identify` | Pass the user's UUID; the call is refused otherwise |
| A parameter that is a `bool` or a list | Send a string or a number; anything else breaks the limit |
| Adding the observer in `main()` | Register the provider; `MagicRouter` refuses an observer after its config is built |
| Expecting `reset()` to change the client id | It does not; the device is the same |

<a name="related-documentation"></a>
## Related Documentation

- [Drivers](drivers.md): what each driver does with these calls.
- [Consent and Opt-Out](consent-and-opt-out.md): what `setOptOut` stops.
- [URL Scrubbing](../guides/url-scrubbing.md): what is masked before anything is sent.
- [Testing](../guides/testing.md): asserting events without a live property.
