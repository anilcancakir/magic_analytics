import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_analytics/magic_analytics.dart';

import '../helpers/test_helpers.dart';

void main() {
  setUp(resetMagic);

  tearDown(MagicRouter.reset);

  group('UrlScrubber.scrub', () {
    test('masks the reset token and the email of a password reset link', () {
      final String scrubbed = UrlScrubber.scrub(
        '/auth/reset-password?token=abc&email=a@b.c',
      );

      expect(
        scrubbed,
        '/auth/reset-password?token=[Filtered]&email=[Filtered]',
      );
      expect(scrubbed, isNot(contains('abc')));
      expect(scrubbed, isNot(contains('a@b.c')));
    });

    test('masks every secret query key, whatever its case', () {
      const List<String> keys = <String>[
        'token',
        'access_token',
        'password',
        'client_secret',
        'signature',
        'credential',
        'api_key',
        'Email',
        'code',
        'invite_code',
      ];

      for (final String key in keys) {
        expect(
          UrlScrubber.scrub('/x?page=2&$key=s3cret#top'),
          '/x?page=2&$key=[Filtered]#top',
          reason: key,
        );
      }
    });

    test('masks a pair in a fragment, the OAuth implicit-flow shape', () {
      expect(
        UrlScrubber.scrub('https://app.test/#access_token=abc&state=1'),
        'https://app.test/#access_token=[Filtered]&state=1',
      );
    });

    test('masks an email address wherever it appears', () {
      expect(
        UrlScrubber.scrub('/users/jane.doe@example.com/edit'),
        '/users/[Filtered]/edit',
      );
      expect(
        UrlScrubber.scrub('/search?q=jane%40example.com'),
        '/search?q=[Filtered]',
      );
      expect(UrlScrubber.scrub('jane+tag@example.co.uk'), '[Filtered]');
    });

    test('masks the segment bound to a registered *token* route param', () {
      MagicRoute.page('/invitations/:token/accept', () => const SizedBox());

      expect(
        UrlScrubber.scrub('/invitations/xyz789/accept?ref=mail'),
        '/invitations/[Filtered]/accept?ref=mail',
      );
      expect(
        UrlScrubber.scrub('https://app.test/invitations/xyz789/accept'),
        'https://app.test/invitations/[Filtered]/accept',
      );
    });

    test('leaves a route that does not match a token route alone', () {
      MagicRoute.page('/invitations/:token/accept', () => const SizedBox());

      expect(
        UrlScrubber.scrub('/api/invitations/xyz789/accept'),
        '/api/invitations/xyz789/accept',
      );
    });

    test('leaves text with nothing secret untouched', () {
      const List<String> clean = <String>[
        '/monitors/:id',
        '/monitors/42?tab=checks',
        'monitors.show',
        'Pro plan',
        '',
      ];

      for (final String text in clean) {
        expect(UrlScrubber.scrub(text), text);
      }
    });
  });
}
