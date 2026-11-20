# Magic Analytics Plugin

Analytics for the Magic Framework: one `Analytics` facade over a GTM driver on web (GA4 through a first-party gateway path), a Firebase driver on iOS and Android, and a null driver when nothing is configured. Consent for ads is always denied; the package is inert until the host sets its IDs.

**Version:** 1.0.0 · **Dart:** >=3.13.0 · **Flutter:** >=3.47.0

## Commands

| Command | Description |
|---------|-------------|
| `flutter test --coverage` | Run all tests with coverage |
| `flutter analyze --no-fatal-infos` | Static analysis |
| `dart format .` | Format all code |
| `flutter pub publish --dry-run` | Pre-publish check |
| `python3 tool/check-docs.py` | Docs structure, links, fragments and ToC anchors; run it after any `doc/` change |

## Architecture

**Pattern**: a facade (`Analytics`) resolving one driver, as Magic's other facades do. Drivers: GTM (web), Firebase (iOS, Android), null (disabled or unconfigured).

```
lib/
├── magic_analytics.dart       # Barrel export, the only public runtime API
└── src/
    ├── facades/               # Analytics facade
    ├── drivers/               # GTM web, Firebase mobile, null
    ├── observers/             # Route observer feeding screen views
    ├── providers/             # AnalyticsServiceProvider: picks the driver, wires observers
    ├── support/               # Event and consent value types
    └── testing/               # Analytics.fake() and its recording driver
tool/check-docs.py             # Offline docs gate, run by docs-link-check.yml
```

The tree lists what the package will hold; add `README.md`, `llms.txt`, `doc/`, `skills/magic-analytics/` and `example/` as they land.

## Post-Change Checklist

After a source code change, sync **before committing**. A change is not done while one of these is stale:

1. **`CHANGELOG.md`**: Add entry under `[Unreleased]` section
2. **`README.md`, `llms.txt` and the `doc/` pages**: Update if features, API, or usage changes
3. **`skills/magic-analytics/SKILL.md`**: Update when the API, a rule or a gotcha changes; its `version:` moves with the release, and the publish check compares it with the tag
4. **`CLAUDE.md`**: Update the architecture tree when files move

## Development Flow (TDD)

Red, green, refactor for every feature, fix or refactor: no production code without a failing test first. After every change `flutter test` stays green and `flutter analyze` reports zero warnings and errors. Never run `dart format` on files you did not change.

## Testing

- No mocking library: fake through contract inheritance, or `Analytics.fake()`
- Tests mirror `lib/src/` and import from `package:magic_analytics/magic_analytics.dart`
- `setUp` runs `MagicApp.reset(); Magic.flush();`; `tearDown` calls `Analytics.unfake()` and `MagicRouter.reset()`

## Key Gotchas

| Mistake | Fix |
|---------|-----|
| Initialising Firebase on web | Never; web goes through GTM only |
| Loading GTM before the device opted in | The GTM driver loads the container only after consent and opt-in checks pass |
| Granting `ad_storage`, `ad_user_data` or `ad_personalization` | Always denied; no config or call may flip them |
| An analytics call throwing into UI flow | Drivers catch and log through Magic's `Log`; a call never blocks or throws |
| An email, token or code in an event param, page location or title | Never send one; the user id is the only identity |
| Relative paths in `pubspec_overrides.yaml` | Use absolute ones; the file is never committed |

## Release

1. Open a `release:` PR that bumps `pubspec.yaml`, `skills/magic-analytics/SKILL.md` and the `Version:` line above, and promotes `[Unreleased]` in `CHANGELOG.md`.
2. After it merges, tag the merge commit with the bare version (`git tag 1.0.0 <merge-sha> && git push origin 1.0.0`, no `v`). `publish.yml` runs from the tag; the pub.dev Admin tab holds repository `anilcancakir/magic_analytics`, tag pattern `{{version}}` and push events only.
3. A failed `validate` is fixed forward: delete the tag (`git push --delete origin <tag>` and `git tag -d <tag>`), fix it on a PR and tag the new merge commit. If only `github-release` fails after pub.dev accepted the version, use "Re-run failed jobs" (never "Re-run all jobs") or run `gh release create <tag> --title <tag> --latest --verify-tag --notes-file <file>`.

## CI

- `ci.yml`: push/PR → `flutter pub get` → `flutter analyze --no-fatal-infos` → `dart format --set-exit-if-changed` → `flutter test --coverage` → codecov upload
- `changelog.yml`: a PR that changes `lib/`, `install.yaml` or `assets/stubs/` must also change `CHANGELOG.md`; Dependabot, `release:` PRs and the `skip-changelog` label are exempt
- `docs-link-check.yml`: every PR runs `python3 tool/check-docs.py` and an offline lychee pass; Mondays an external-link pass
- `publish.yml`: tag on master → version stamps (tag, pubspec, skill) → analyze, format, test, dry-run, pana 160/160, changelog section → OIDC publish → GitHub Release
