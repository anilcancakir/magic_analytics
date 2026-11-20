# magic_analytics example

A Magic app that registers `AnalyticsServiceProvider` and shows whether analytics is on, with buttons that send an event, identify a user and toggle the opt-out. Analytics stays off until `.env` carries the keys.

```bash
cd example
# set ANALYTICS_ENABLED, GTM_CONTAINER_ID and GTM_GATEWAY_PATH in .env, then:
flutter run -d chrome
```

On web the container loads from `GTM_GATEWAY_PATH` on the same origin, so the dev server or a reverse proxy has to forward that path to `GTM-XXXXXXX.fps.goog`; see `doc/getting-started/installation.md`. On iOS and Android set `firebase_options` in `lib/config/analytics.dart` after `flutterfire configure --platforms=ios,android`.

`.env` is a bundled asset (`flutter: assets:` in `pubspec.yaml`) and ships with everything off. `lib/config/analytics.dart` is the file `plugin:install` publishes into an app, copied here so the example runs on its own.
