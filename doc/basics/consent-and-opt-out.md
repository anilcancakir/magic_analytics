# Consent and Opt-Out

Ads consent is always denied, and a device can opt out of everything else with `Analytics.setOptOut`.

- [Quick Reference](#quick-reference)
- [Ads Stay Denied](#ads-stay-denied)
- [The Device Opt-Out](#the-device-opt-out)
- [What Each Driver Does](#what-each-driver-does)
- [Gotchas](#gotchas)
- [Related Documentation](#related-documentation)

<a name="quick-reference"></a>
## Quick Reference

Persist the choice yourself, and restore it before the first page view:

```dart
import 'package:magic_analytics/magic_analytics.dart';

Future<void> restoreConsent(bool storedOptOut) async {
  await Analytics.setOptOut(storedOptOut);
}

Future<void> onToggle(bool optedOut, Future<void> Function(bool) persist) async {
  await Analytics.setOptOut(optedOut);
  await persist(optedOut);
}
```

| Member | Does |
|:-------|:-----|
| `Analytics.setOptOut(true)` | Stops collection on this device |
| `Analytics.setOptOut(false)` | Resumes it |
| `Analytics.isOptedOut` | The current state, in memory |

<a name="ads-stay-denied"></a>
## Ads Stay Denied

`ad_storage`, `ad_user_data` and `ad_personalization` are denied on every start, on every platform, and no config key or call can grant them. Analytics storage is granted by default; the device opt-out is what stops collection.

<a name="the-device-opt-out"></a>
## The Device Opt-Out

The opt-out is held in memory only. The package stores nothing, so the host persists the choice (a preference, or the account setting once signed in) and calls `Analytics.setOptOut` on every start, before the first page view. A start that forgets to call it collects again.

While a device is opted out, every call except `setOptOut`, `reset` and `clientId` is a no-op that reaches no driver. `setOptOut` itself is always forwarded to the driver, so the driver can stop collecting, and `reset` still runs so a sign-out clears the identity.

<a name="what-each-driver-does"></a>
## What Each Driver Does

| Driver | On opt-out | On opt back in |
|:-------|:-----------|:---------------|
| `GtmWebDriver` | Never loads the container while opted out. After it loaded, pushes a consent update that denies `analytics_storage` and stops every send | Grants `analytics_storage` again |
| `FirebaseDriver` | Calls `setAnalyticsCollectionEnabled(false)`; the first-use initialisation does not enable collection | Calls `setAnalyticsCollectionEnabled(true)` |
| `NullDriver` | Nothing to stop | Nothing |

The Firebase driver never calls `resetAnalyticsData`: opting out keeps the app instance id, so opting back in is the same device.

<a name="gotchas"></a>
## Gotchas

| Mistake | Fix |
|:--------|:----|
| Calling `setOptOut` after the first page view | Restore the stored choice during boot, before the router renders |
| Assuming the package remembers the choice | It is in memory only; persist it and set it on every start |
| Reading `isOptedOut` before restoring | It is `false` until `setOptOut` is called |
| Trying to grant `ad_storage` | There is no switch; ads are denied by design |

<a name="related-documentation"></a>
## Related Documentation

- [Drivers](drivers.md): the transport behind each platform.
- [Facade and Provider](facade-and-provider.md): `reset` and the auth listener.
