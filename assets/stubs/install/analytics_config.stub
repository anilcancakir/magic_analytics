import 'package:magic/magic.dart';

/// Analytics configuration, read by `magic_analytics`.
///
/// Everything is off until you set the keys: with `ANALYTICS_ENABLED` anything
/// but true the package binds a driver that sends nothing, and on web the GTM
/// container only loads once BOTH `GTM_CONTAINER_ID` and `GTM_GATEWAY_PATH`
/// are set, so it is never fetched from Google's own host.
///
/// Through [Env.filled], not [env]: a present-but-blank key (`KEY=""`) must
/// read as nothing, never as the two-character string `""`.
///
/// This file was generated once by `plugin:install` from `magic_analytics`'s
/// own install manifest, and is yours to edit from here.
Map<String, dynamic> get analyticsConfig => {
  'analytics': {
    'enabled': env('ANALYTICS_ENABLED', false),
    'gtm': {
      'container_id': Env.filled('GTM_CONTAINER_ID', ''),
      'gateway_path': Env.filled('GTM_GATEWAY_PATH', ''),
    },

    // Becomes `() => DefaultFirebaseOptions.currentPlatform` (from the
    // `firebase_options.dart` that `flutterfire configure --platforms=ios,android`
    // generates) once you run it, and stays null on web, where Firebase is
    // never initialised. Null keeps the mobile driver inert.
    'firebase_options': null,
  },
};
