# Testing

Test code that sends analytics with `Analytics.fake()`, which records what passed validation, scrubbing and the opt-out gate, with no live property.

- [Quick Reference](#quick-reference)
- [Faking the Facade](#faking-the-facade)
- [Widget Tests](#widget-tests)
- [Reading the Record](#reading-the-record)
- [Gotchas](#gotchas)
- [Related Documentation](#related-documentation)

<a name="quick-reference"></a>
## Quick Reference

| You want to check | Use |
|:------------------|:----|
| An event was sent | `fake.assertTracked('name')` |
| An event was not sent | `fake.assertNotTracked('name')` |
| Nothing reached the driver | `fake.assertNothingSent()` |
| Which events were sent | `fake.events` |
| Which page views were sent | `fake.screens` |
| The identity at each call | `RecordedAnalyticsCall.userId`, `userProperties`, `defaultParams` |

No mocking library is needed: the package fakes through contract inheritance.

<a name="faking-the-facade"></a>
## Faking the Facade

`Analytics.fake()` binds the real `AnalyticsManager` over a `FakeAnalytics` driver and returns the driver. Validation, scrubbing, opt-out and reset apply exactly as in the app, and the fake records what reached the driver.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_analytics/magic_analytics.dart';

void main() {
  setUp(() {
    MagicApp.reset();
    Magic.flush();
  });

  tearDown(() {
    Analytics.unfake();
    MagicRouter.reset();
  });

  test('creating a monitor sends one event', () async {
    final FakeAnalytics fake = Analytics.fake();

    await Analytics.track('monitor_created', {'monitor_type': 'http'});

    fake.assertTracked('monitor_created');
    expect(fake.events.single.parameters, {'monitor_type': 'http'});
  });
}
```

`Analytics.unfake()` removes the fake; the next call resolves the provider's binding again. Call `Analytics.fake()` after the provider registers, because `register()` binds a real manager that would replace a fake bound earlier.

<a name="widget-tests"></a>
## Widget Tests

In a `testWidgets` body, call `Analytics.fake()` inside the body, not in `setUp`. The manager's send queue has to be created in the widget test's fake-async zone for a pump to drain it:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_analytics/magic_analytics.dart';

void main() {
  tearDown(() {
    Analytics.unfake();
    MagicRouter.reset();
  });

  testWidgets('the page view carries the pattern, never the id', (
    tester,
  ) async {
    final FakeAnalytics fake = Analytics.fake();

    MagicRoute.page('/', () => const SizedBox());
    MagicRoute.page('/monitors/:id', () => const SizedBox());
    MagicRouter.instance.addObserver(AnalyticsNavigatorObserver());

    await tester.pumpWidget(
      WidgetsApp.router(
        color: const Color(0xFF000000),
        routerConfig: MagicRouter.instance.routerConfig,
      ),
    );
    await tester.pumpAndSettle();

    MagicRouter.instance.to('/monitors/4711');
    await tester.pumpAndSettle();

    expect(fake.screens.last.name, '/monitors/:id');
    expect(fake.screens.toString(), isNot(contains('4711')));
  });
}
```

A call made without `await` (an auth listener, the observer) lands on a later microtask, so `await Future<void>.delayed(Duration.zero)` before you read the record in a plain test.

<a name="reading-the-record"></a>
## Reading the Record

Each `RecordedAnalyticsCall` has a `kind` (`RecordedCallKind`), a `name`, its `parameters` and a copy of the identity the transport held when the call arrived, so a test can prove which user and which team facts an event carried. `FakeAnalytics` also exposes the live `userId`, `userProperties`, `defaultParams`, `optedOut` and `calls`; set `clientIdValue` to fake `Analytics.clientId()`.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_analytics/magic_analytics.dart';

void main() {
  test('team facts ride on the event, the user stays user-level', () async {
    final FakeAnalytics fake = Analytics.fake();

    await Analytics.identify('user-a');
    await Analytics.setDefaultParams({'team_plan': 'pro'});
    await Analytics.track('monitor_created');

    final RecordedAnalyticsCall event = fake.events.single;

    expect(event.userId, 'user-a');
    expect(event.defaultParams, {'team_plan': 'pro'});
    expect(event.userProperties, isEmpty);
  });
}
```

<a name="gotchas"></a>
## Gotchas

| Mistake | Fix |
|:--------|:----|
| Calling `Analytics.fake()` before the provider registers | Fake after `register()`, or the real manager replaces the fake |
| Faking in `setUp` of a `testWidgets` test | Call `Analytics.fake()` inside the test body |
| Leaving the fake bound after a test | `Analytics.unfake()` in `tearDown` |
| A route that outlives its test | `MagicRouter.reset()` in `tearDown` |
| An event that never shows up | A limit was broken: debug fails an `assert`, release drops the call; check the name and the values |
| Asserting on a call made while opted out | An opted-out manager reaches no driver, so the fake records nothing |

<a name="related-documentation"></a>
## Related Documentation

- [Facade and Provider](../basics/facade-and-provider.md): the limits a test trips over.
- [Consent and Opt-Out](../basics/consent-and-opt-out.md): what an opted-out device records.
