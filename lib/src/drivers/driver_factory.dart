// Conditional export that picks the platform arm of `createAnalyticsDriver`.
//
// The stub is the default and resolves only when neither guard matches, which
// no real Flutter build target does. The web guard keys on `dart:js_interop`
// rather than the legacy `dart:html`, which is absent under a wasm web
// compile; guarding on it would fall through to the io arm and hand a browser
// the Firebase driver. Every arm exposes the same signature:
// `AnalyticsDriver createAnalyticsDriver(Map<String, dynamic> config)`.
export 'driver_factory_stub.dart'
    if (dart.library.js_interop) 'driver_factory_web.dart'
    if (dart.library.io) 'driver_factory_io.dart';
