<p align="center">
  <img src="https://raw.githubusercontent.com/anilcancakir/magic_analytics/master/.github/magic-logo.svg" width="120" alt="Magic Logo" />
</p>

<h1 align="center">Magic Analytics</h1>

<p align="center">
  <strong>GA4 for Magic apps, with ads consent denied.</strong><br/>
  One <code>Analytics</code> facade sends through Google Tag Manager on web, served from your own domain, and through Firebase on iOS and Android. Emails and tokens are scrubbed before anything leaves. Without IDs it does nothing.
</p>

<p align="center">
  <a href="https://pub.dev/packages/magic_analytics"><img src="https://img.shields.io/pub/v/magic_analytics.svg" alt="pub package"></a>
  <a href="https://github.com/anilcancakir/magic_analytics/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/anilcancakir/magic_analytics/ci.yml?branch=master&label=CI" alt="CI"></a>
  <a href="https://codecov.io/gh/anilcancakir/magic_analytics"><img src="https://codecov.io/gh/anilcancakir/magic_analytics/graph/badge.svg" alt="codecov"></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"></a>
  <a href="https://pub.dev/packages/magic_analytics/score"><img src="https://img.shields.io/pub/points/magic_analytics" alt="pub points"></a>
</p>

<p align="center">
  <a href="https://anilcancakir.com/magic/docs/analytics">Documentation</a> ·
  <a href="https://pub.dev/packages/magic_analytics">pub.dev</a> ·
  <a href="https://github.com/anilcancakir/magic_analytics/issues">Issues</a>
</p>

## At a glance

| Fact | Value |
|---|---|
| Package | [`magic_analytics`](https://pub.dev/packages/magic_analytics) |
| Install | `flutter pub add magic_analytics`, then `dart run magic:dowel plugin:install magic_analytics` |
| Import | `package:magic_analytics/magic_analytics.dart` |
| Entry points | `Analytics` (facade), `AnalyticsServiceProvider`, `AnalyticsDriver`, `UrlScrubber`, `Analytics.fake()` |
| Platforms | Web through GTM, iOS and Android through Firebase; Firebase is never initialised on web |
| Requires | Dart >=3.13, Flutter >=3.47, `magic` ^1.0.0 |
| Dependencies | `magic`, `firebase_core` ^5.2.0, `firebase_analytics` ^13.1.0, `web`; dowel runs the installer |
| License | MIT |

## Install

```bash
flutter pub add magic_analytics
dart run magic:dowel plugin:install magic_analytics
```

The installer publishes `lib/config/analytics.dart` (your own editable copy that reads `ANALYTICS_ENABLED`, `GTM_CONTAINER_ID` and `GTM_GATEWAY_PATH` from `.env`), registers `AnalyticsServiceProvider` in `lib/config/app.dart` and adds `analyticsConfig` to the config factories. It writes no native file and cannot set up your web server; the installation guide lists both steps.

```dart
import 'package:magic/magic.dart';
import 'package:material_ui/material_ui.dart';

import 'config/analytics.dart'; // published by plugin:install

Future<void> main() async {
  await Magic.init(
    configFactories: [
      () => analyticsConfig,
      // Keep every other config factory your main() already passes.
    ],
  );

  runApp(MagicApplication(title: 'My App'));
}
```

## Events and identity

Send an event, identify the user and tag the team. Team facts go through `setDefaultParams`, which replaces the set and rides on every event; `setUserProperties` is for the user only.

```dart
import 'package:magic_analytics/magic_analytics.dart';

Future<void> afterSignIn(String userUuid, String teamPlan) async {
  await Analytics.identify(userUuid);
  await Analytics.setDefaultParams({'team_plan': teamPlan});
  await Analytics.track('monitor_created', {'monitor_type': 'http'});
}
```

| Call | Effect |
|------|--------|
| `track(name, [parameters])` | An event with string or number parameters |
| `identify(userId)` | The GA4 user id: a UUID, never an email |
| `setUserProperties(properties)` | User-level properties; `null` clears one |
| `setDefaultParams(parameters)` | Replaces the parameters sent with every event |
| `reset()` | Nulls the user id, the user properties and the defaults; keeps the client id |

GA4 limits: names of 40 characters, 25 parameters with the defaults, string values of 100, user property names of 24 and values of 36. A call that breaks one throws an `AssertionError` in debug and is dropped with a log line in release. A driver failure is logged and never reaches the caller: the returned future always completes.

## Page views

`AnalyticsServiceProvider` adds an observer to `MagicRouter` that reports each named page with its route name as the title (the pattern when the route has no name) and its route pattern (`/monitors/:id`, never `/monitors/42`) as the location. No id, token or email leaves, and every monitor's page counts as one page. The provider also resets analytics when the signed-in user signs out or changes.

A view the router does not see (a tab inside one page, say) goes through `screen` by hand:

```dart
import 'package:magic_analytics/magic_analytics.dart';

Future<void> onTabChanged(String tab) {
  return Analytics.screen('monitor_$tab', location: '/monitors/:id/$tab');
}
```

| Navigation | Page view |
|------------|-----------|
| Push or replace a named page | Yes: title is the route name, location its path pattern, referrer the previous location |
| Pop back to a named page | Yes, for the page revealed |
| A dialog, bottom sheet or other unnamed route | No |
| Closing a dialog | No: the page below is the same view |

## Web and mobile

| Platform | Driver | What it does |
|----------|--------|--------------|
| Web | `GtmWebDriver` | Loads the container lazily on the first send, from `GTM_GATEWAY_PATH` on your origin; never on an opted-out device |
| iOS, Android | `FirebaseDriver` | Initialises Firebase on first use, enables collection unless opted out, never calls `resetAnalyticsData` |
| Not configured | `NullDriver` | Sends nothing |

On web, proxy a first-party path to your container's `GTM-XXXXXXX.fps.goog` host (Google tag gateway); the container is never requested from `googletagmanager.com`. The container itself needs a GA4 Event tag on a Custom Event trigger (event name `{{Event}}`), data layer variables for the page and user fields, and `analytics_storage` required on both tags; the Drivers doc lists them. On mobile, run `flutterfire configure --platforms=ios,android` and set `firebase_options` in the config.

## Consent

`ad_storage`, `ad_user_data` and `ad_personalization` are denied on every start and nothing grants them. A device can opt out with `Analytics.setOptOut(true)`. The opt-out is held in memory, so persist it yourself and call `setOptOut` before the first page view:

```dart
import 'package:magic_analytics/magic_analytics.dart';

// `storedOptOut` is the value your app saved when the user chose.
Future<void> restoreOptOut(bool storedOptOut) {
  return Analytics.setOptOut(storedOptOut);
}
```

| While opted out | Behaviour |
|-----------------|-----------|
| `track`, `screen`, `identify`, `setUserProperties`, `setDefaultParams` | No-op; nothing reaches the driver |
| `setOptOut`, `reset`, `clientId` | Still run |
| Web | A container not yet loaded stays unloaded; a loaded one gets `analytics_storage` denied |
| iOS, Android | Firebase collection is turned off |

## Testing

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_analytics/magic_analytics.dart';

void main() {
  tearDown(Analytics.unfake);

  test('creating a monitor sends one event', () async {
    final FakeAnalytics fake = Analytics.fake();

    await Analytics.track('monitor_created');

    fake.assertTracked('monitor_created');
  });
}
```

The fake sits behind the real manager, so it records only what passed validation, scrubbing and the opt-out gate.

| Member | Use |
|--------|-----|
| `assertTracked(name)`, `assertNotTracked(name)` | Whether an event was sent |
| `assertNothingSent()` | No call reached the driver |
| `events`, `screens`, `calls` | The recorded calls, each with the user id, user properties and defaults held at that moment |
| `userId`, `userProperties`, `defaultParams`, `optedOut` | The identity the driver holds now |

Call `Analytics.fake()` after the provider registers, since `register()` replaces an earlier fake. In a `testWidgets` test call it inside the body, not in `setUp`: the send queue needs the widget test's zone.

## For AI coding agents

Rules for an agent writing code against this package. Each one is a mistake the maintainers want to avoid.

| Do | Because |
|----|---------|
| Register `AnalyticsServiceProvider` in the `providers` list, after error reporting | The observer has to be added before the router builds its config |
| Call `Analytics.identify` with the user's UUID | An email is refused, and the provider never identifies anyone |
| Put team facts in `setDefaultParams` and user facts in `setUserProperties` | Defaults replace the set per team; user properties are user-level and survive a team switch |
| Set both `GTM_CONTAINER_ID` and `GTM_GATEWAY_PATH` | The container is never loaded from Google's own host |
| Leave `firebase_options` `null` on web | Firebase is never initialised there |
| Persist the opt-out and call `setOptOut` before the first page view | It is in memory only |
| Send strings and numbers inside the GA4 limits | A call that breaks one fails an assert in debug and is dropped in release |
| Call `Analytics.fake()` after the provider registers, and inside the body (not `setUp`) of a `testWidgets` test | `register()` would replace an earlier fake, and the send queue needs the widget test's zone |

## Dependencies

`magic` for the container, `Auth.stateNotifier`, `MagicRouter` and `Log`; `firebase_core` and `firebase_analytics` for the mobile driver; `web` for the GTM driver's script and cookie access; `dowel` to run the installer through `dart run magic:dowel`, which resolves `package:magic_analytics/cli.dart` (`MagicAnalyticsDowelProvider`, no commands).

## Links

- [Documentation](https://anilcancakir.com/magic/docs/analytics/getting-started/installation): installation, the facade, drivers, consent, testing and URL scrubbing
- [API reference](https://pub.dev/documentation/magic_analytics/latest/)
- [llms.txt](llms.txt) and the [agent skill](skills/magic-analytics/SKILL.md) for AI coding agents: `npx skills add anilcancakir/magic_analytics`
- [Changelog](CHANGELOG.md)
- [Report an issue](https://github.com/anilcancakir/magic_analytics/issues)
- [Security policy](SECURITY.md)

## License

MIT, see [LICENSE](LICENSE). Built by [Anılcan Çakır](https://anilcancakir.com).
