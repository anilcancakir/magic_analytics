import 'package:magic/magic.dart';
import 'package:magic_analytics/magic_analytics.dart';
import 'package:material_ui/material_ui.dart';

import 'config/analytics.dart';

Future<void> main() async {
  await Magic.init(
    configFactories: [
      () => analyticsConfig,
    ],
    configs: [
      {
        'app': {
          'providers': [
            (app) => AnalyticsServiceProvider(app),
          ],
        },
      },
    ],
  );

  runApp(const ExampleApp());
}

/// One screen: whether a driver is sending, and buttons that call the facade.
class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'magic_analytics example',
      home: Scaffold(
        appBar: AppBar(title: const Text('magic_analytics example')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                Config.get('analytics.enabled') == true
                    ? 'Analytics is on'
                    : 'Analytics is off: set ANALYTICS_ENABLED in .env',
              ),
              Text(
                Analytics.isOptedOut ? 'This device opted out' : 'Collecting',
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Analytics.track('example_clicked', {
                  'button': 'track',
                }),
                child: const Text('Track an event'),
              ),
              const SizedBox(height: 8),
              // An opaque id, never an email: the facade refuses one.
              FilledButton(
                onPressed: () =>
                    Analytics.identify('0b8f6f9e-5f55-4a0e-9d10-3c1d6a2c9a11'),
                child: const Text('Identify a user'),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () async {
                  await Analytics.setOptOut(!Analytics.isOptedOut);
                  setState(() {});
                },
                child: Text(
                  Analytics.isOptedOut ? 'Opt back in' : 'Opt out',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
