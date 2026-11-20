# URL Scrubbing

`UrlScrubber` masks secrets in a URL or any text before it is sent: every page location, referrer, title and string parameter passes through it.

- [Quick Reference](#quick-reference)
- [The Three Rules](#the-three-rules)
- [Where It Runs](#where-it-runs)
- [Limits](#limits)
- [Gotchas](#gotchas)
- [Related Documentation](#related-documentation)

<a name="quick-reference"></a>
## Quick Reference

```dart
import 'package:magic_analytics/magic_analytics.dart';

void main() {
  final String safe = UrlScrubber.scrub(
    'https://app.example.com/reset?email=ada@example.com&token=abc123',
  );

  // https://app.example.com/reset?email=[Filtered]&token=[Filtered]
  assert(safe.contains(UrlScrubber.filtered));
}
```

| Member | Does |
|:-------|:-----|
| `UrlScrubber.scrub(text)` | Returns `text` with every secret the three rules find replaced |
| `UrlScrubber.filtered` | The replacement, `[Filtered]` |

A masked value becomes `[Filtered]` rather than disappearing, so a report still shows that the URL carried a secret and where. Text with nothing to mask comes back unchanged.

<a name="the-three-rules"></a>
## The Three Rules

Applied in this order:

1. **Query values.** A `?key=value`, `&key=value` or `#key=value` pair whose key contains `token`, `password`, `secret`, `signature`, `credential`, `api_key`, `email` or `code` (any case) keeps its key and loses its value.
2. **Route-bound segments.** A path segment sitting where a registered Magic route has a param whose name contains `token` is masked. The routes are read from `MagicRouter.instance.allRoutes` at scrub time, so a route inside a layout group, or one added after boot, is covered.
3. **Email addresses.** Anything shaped like an email address, raw or with a percent-encoded `@`, is masked wherever it appears.

Rules 1 and 2 mirror magic_sentry's token scrubber, copied rather than imported so this package does not depend on Sentry.

<a name="where-it-runs"></a>
## Where It Runs

The facade scrubs for you, so app code never calls it on the way out:

| Input | Scrubbed |
|:------|:---------|
| String values in `track` and `setDefaultParams` | Yes, before the length limit applies |
| `setUserProperties` values | Yes |
| `screen` name, location and referrer | Yes |
| `identify` | Refused when scrubbing would change the id |
| Event, parameter and property names | Not scrubbed; they are code, and are validated against the GA4 name rules |

The page view observer adds a second guard: it reports the route PATTERN (`/monitors/:id`), so the real URL never reaches the scrubber at all. The scrubber covers the strings an app passes in by hand.

<a name="limits"></a>
## Limits

It masks values it can recognise: a key that names a secret, a route param that says `token`, an email shape. A secret in a free-text parameter that matches none of these is not caught. Do not put one there.

Name a credential route param with `token` in it (`:resetToken`) or the route rule does not see it.

<a name="gotchas"></a>
## Gotchas

| Mistake | Fix |
|:--------|:----|
| A route param named `:key` or `:hash` carrying a credential | Rename it with `token` in it; the rule matches on the name |
| Scrubbing before a route is registered | Register routes first; the rule reads `MagicRouter.instance.allRoutes` |
| Putting an email in a parameter to read it back later | Send the user's UUID; the email is masked on the way out |
| Relying on the scrubber for a free-text secret | Keep secrets out of parameters |

<a name="related-documentation"></a>
## Related Documentation

- [Facade and Provider](../basics/facade-and-provider.md): where each call is scrubbed.
- [Testing](testing.md): asserting that a page view carries the pattern.
