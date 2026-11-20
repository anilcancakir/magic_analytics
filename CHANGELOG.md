# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added

- **Package scaffold.** Repository files, workflows and the docs gate required by the package standard. (`pubspec.yaml`, `.github/`, `tool/check-docs.py`)
- **The `Analytics` facade and `AnalyticsManager`.** `track`, `screen`, `identify`, `setUserProperties`, `setDefaultParams`, `setOptOut`, `reset` and `clientId`, validated against the GA4 limits (an `assert` in debug, a dropped call with a log in release), scrubbed, gated on the device opt-out and sent to the driver in call order. A driver error is logged and never thrown into UI flow. (`lib/src/facades/analytics.dart`)
- **Three drivers behind one contract.** `GtmWebDriver` loads a Google Tag Manager container lazily from a first-party gateway path and never on an opted-out device; `FirebaseDriver` serves iOS and Android and Firebase is never initialised on web; `NullDriver` sends nothing, so the package is inert until `ANALYTICS_ENABLED` (`true`, `1` or `yes`) and the IDs are set. Ad signals are denied on every start; analytics storage is granted unless the device opts out. Before `gtm.js` the GTM bootstrap pre-seeds `page_location` and `page_referrer` with the origin root, and the first page view's referrer is that root, so the Google tag never reads a tokenised address bar. (`lib/src/drivers/`)
- **`AnalyticsServiceProvider` and `AnalyticsNavigatorObserver`.** The provider binds the manager, adds the page view observer to `MagicRouter` and resets analytics when the signed-in user signs out or changes. Page views carry the route name as the title and the route pattern as the location, never the real URL. (`lib/src/analytics_service_provider.dart`, `lib/src/observers/analytics_navigator_observer.dart`)
- **`UrlScrubber`.** Masks secret query values, route-bound token segments and email addresses in every string that leaves the device. (`lib/src/support/url_scrubber.dart`)
- **`Analytics.fake()` and `FakeAnalytics`.** A recording driver behind the real manager, with `assertTracked`, `assertNotTracked` and `assertNothingSent`. (`lib/src/testing/fake_analytics.dart`)
- **`install.yaml` and the config stub.** `plugin:install` publishes `lib/config/analytics.dart`, registers `AnalyticsServiceProvider`, injects the `analyticsConfig` factory and prints the web gateway, `flutterfire configure` and native key steps. (`install.yaml`, `assets/stubs/install/analytics_config.stub`)
- `lib/cli.dart` with `MagicAnalyticsDowelProvider`, so `plugin:install magic_analytics` registers under dowel. It contributes no commands, stays Flutter-free, and `dowel` ^1.0.0 is a new dependency. (`lib/cli.dart`, `lib/src/cli/analytics_dowel_provider.dart`, `pubspec.yaml`)
- `doc/`: six pages in the repository's docs standard (installation, facade and provider, drivers, consent and opt-out, testing and URL scrubbing), checked by `tool/check-docs.py`. The drivers page lists the GTM container setup: a GA4 Event tag, data layer variables, a shared Event Settings Variable and `analytics_storage` required on both tags.
- `llms.txt`, `skills/magic-analytics` and `README.md`: the package for people and for AI coding agents. The skill is installed with `npx skills add anilcancakir/magic_analytics` and stays out of the pub.dev archive.
- `example/`: a runnable Magic app with the provider registered and buttons that send an event, identify a user and toggle the opt-out.
