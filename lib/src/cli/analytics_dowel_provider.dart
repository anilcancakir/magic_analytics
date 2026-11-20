import 'package:dowel/dowel.dart';

/// The dowel provider for Magic Analytics.
///
/// Contributes no commands. It exists because dowel `plugin:install` resolves
/// a plugin through `package:magic_analytics/cli.dart` and registers the class
/// named `<PascalCase package>DowelProvider` from it.
class MagicAnalyticsDowelProvider extends DowelServiceProvider {
  @override
  String get providerName => 'magic_analytics';

  @override
  List<DowelCommand> commands() => <DowelCommand>[];
}
