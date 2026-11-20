# Installation

Add `magic_analytics` to a Magic app, run the installer, set the keys and serve Google Tag Manager from your own domain on web.

- [Install](#install)
- [Requirements](#requirements)
- [Register the Config and the Provider](#register-the-config-and-the-provider)
- [Configuration](#configuration)
- [Web Gateway](#web-gateway)
- [iOS and Android](#ios-and-android)
- [Identify the User](#identify-the-user)
- [Verify](#verify)
- [Related Documentation](#related-documentation)

<a name="install"></a>
## Install

```bash
flutter pub add magic_analytics
dart run magic:dowel plugin:install magic_analytics
```

The installer reads the package's `install.yaml`, publishes `lib/config/analytics.dart` (your own copy, free to edit), injects `AnalyticsServiceProvider` into the `providers` list of `lib/config/app.dart` and adds `analyticsConfig` to the config factories of `lib/main.dart`. It writes no native file and cannot set up your web server: the steps below are yours.

Nothing is sent until you set the keys. With `ANALYTICS_ENABLED` anything but `true`, the provider binds a driver that sends nothing.

<a name="requirements"></a>
## Requirements

| Requirement | Value |
|:------------|:------|
| Dart | `>=3.13.0` |
| Flutter | `>=3.47.0` |
| Magic | `^1.0.0`, installed and bootstrapped (`lib/config/app.dart` exists) |
| Firebase | `firebase_core` and `firebase_analytics`, pulled in by the package; used on iOS and Android only |
| Web | A web server that can proxy one path to `GTM-XXXXXXX.fps.goog` |

<a name="register-the-config-and-the-provider"></a>
## Register the Config and the Provider

Add the config factory to the list `Magic.init` receives, and keep every factory your `main()` already passes:

```dart
import 'package:magic/magic.dart';
import 'package:magic_analytics/magic_analytics.dart';
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

The provider entry goes in the `providers` list of `lib/config/app.dart`, after the providers that report errors, so a failure while analytics boots is still reported:

```dart
import 'package:magic_analytics/magic_analytics.dart';

final List<Object> providers = [
  // ...your other providers, error reporting first
  (app) => AnalyticsServiceProvider(app),
];
```

`boot()` adds a page view observer to `MagicRouter`, which refuses one after it has built its `routerConfig`: keep the provider in the list instead of adding the observer yourself.

<a name="configuration"></a>
## Configuration

`lib/config/analytics.dart` reads these `.env` keys:

| Key | Default | Purpose |
|:----|:--------|:--------|
| `ANALYTICS_ENABLED` | `false` | The master switch. Anything but `true` keeps the driver that sends nothing. |
| `GTM_CONTAINER_ID` | `''` | The container, `GTM-XXXXXXX`. Web only. |
| `GTM_GATEWAY_PATH` | `''` | The first-party path that serves the container, such as `/metrics`. Web only. |

The container loads only when both GTM keys are filled, so it is never requested from Google's own host. The keys go through `Env.filled`, which reads a blank value (`KEY=""`) as nothing.

The map also holds `firebase_options`, `null` by default, which turns the mobile driver on once it is set; see [iOS and Android](#ios-and-android). `Env` reads the `.env` you bundle, not `--dart-define`, so write the keys into the file the build ships.

<a name="web-gateway"></a>
## Web Gateway

On web the container is served from a path on your own origin and never from `googletagmanager.com`. Proxy that path to your container's Google tag gateway host, `GTM-XXXXXXX.fps.goog`, in the web server in front of the app, then point the config at it:

```bash
ANALYTICS_ENABLED=true
GTM_CONTAINER_ID=GTM-XXXXXXX
GTM_GATEWAY_PATH=/metrics
```

The driver requests `/metrics/?id=GTM-XXXXXXX` on the page's origin. The path may be written `metrics`, `/metrics` or `/metrics/`. The container must send no page view of its own: its GA4 configuration sets `send_page_view` to `false`, because the driver pushes each page view with a pattern location instead.

<a name="ios-and-android"></a>
## iOS and Android

Run FlutterFire once, then hand the generated options to the config:

```bash
flutterfire configure --platforms=ios,android
```

In `lib/config/analytics.dart` set `'firebase_options': () => DefaultFirebaseOptions.currentPlatform`, with `DefaultFirebaseOptions` imported from the `firebase_options.dart` FlutterFire wrote. Leave it `null` on web: Firebase is never initialised there. The driver initialises Firebase on first use when your app has not done it.

Keep collection off until the driver switches it on, and keep ads denied, with these native keys.

iOS, in `Info.plist`:

| Key | Value |
|:----|:------|
| `FIREBASE_ANALYTICS_COLLECTION_ENABLED` | `false` |
| `FirebaseAutomaticScreenReportingEnabled` | `false` |
| `GOOGLE_ANALYTICS_DEFAULT_ALLOW_ANALYTICS_STORAGE` | `true` |
| `GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_STORAGE` | `false` |
| `GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_USER_DATA` | `false` |
| `GOOGLE_ANALYTICS_DEFAULT_ALLOW_AD_PERSONALIZATION_SIGNALS` | `false` |

Android, as `<meta-data>` inside `<application>` in `AndroidManifest.xml`:

| Name | Value |
|:-----|:------|
| `firebase_analytics_collection_enabled` | `false` |
| `google_analytics_automatic_screen_reporting_enabled` | `false` |
| `google_analytics_default_allow_analytics_storage` | `true` |
| `google_analytics_default_allow_ad_storage` | `false` |
| `google_analytics_default_allow_ad_user_data` | `false` |
| `google_analytics_default_allow_ad_personalization_signals` | `false` |

Automatic screen reporting is off because the observer sends the page views, and two sources would count each one twice.

<a name="identify-the-user"></a>
## Identify the User

The package never decides who the user is. After sign-in, call `Analytics.identify` with an opaque id (a UUID), and set the user's opt-out before the first page view; see [Consent and Opt-Out](../basics/consent-and-opt-out.md).

```dart
import 'package:magic_analytics/magic_analytics.dart';

Future<void> onSignedIn(String userUuid) async {
  await Analytics.identify(userUuid);
}
```

<a name="verify"></a>
## Verify

Set the keys, run the app and open GA4 Realtime or the GTM preview. The Firebase driver sends once the options are set and the platform is iOS or Android; the web driver injects its script on the first event, so nothing appears in the network tab before then.

```dart
import 'package:magic_analytics/magic_analytics.dart';

Future<void> verify() async {
  await Analytics.track('analytics_installed');
}
```

With the keys empty `Analytics.track` completes and sends nothing.

<a name="related-documentation"></a>
## Related Documentation

- [Facade and Provider](../basics/facade-and-provider.md): the calls, the limits and what the provider wires.
- [Drivers](../basics/drivers.md): which driver runs where and what each pushes.
- [Consent and Opt-Out](../basics/consent-and-opt-out.md): ads denied, the device opt-out.
