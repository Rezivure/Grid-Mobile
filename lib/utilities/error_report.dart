/// Builds the block of text a user copies out of an error dialog and pastes
/// into Discord when asking for help.
///
/// Passkey signup/login failures are the one place where a user can get stuck
/// with no self-service way out: there is no SMS fallback any more, so the only
/// escape hatch is a human. That makes the *quality of the paste* the whole
/// feature — a bare "Something went wrong" tells the team nothing, while a
/// report carrying the action, platform, build and raw error is usually enough
/// to diagnose without a back-and-forth.
///
/// Pure function — no I/O, no BuildContext — so it can be unit-tested and so
/// the caller stays in control of what gets disclosed.
library;

/// Assembles a support-report string.
///
/// [action] is what the user was doing in plain language ("Passkey signup").
/// [error] is the raw thrown object; its `toString()` is included verbatim
/// because the exact message is what makes a report actionable.
/// [timestamp] is converted to UTC so reports from different timezones sort
/// and correlate against server logs without ambiguity.
///
/// [username], [appVersion] and [platform] are optional: any that are null or
/// blank are omitted rather than rendered as "null". No phone number, token or
/// credential is ever included — the caller cannot pass one.
String buildErrorReport({
  required String action,
  required Object error,
  required DateTime timestamp,
  String? username,
  String? appVersion,
  String? platform,
}) {
  final lines = <String>[
    'Grid error report',
    'Action: $action',
    'Time: ${timestamp.toUtc().toIso8601String()}',
  ];

  void addIfPresent(String label, String? value) {
    final v = value?.trim();
    if (v == null || v.isEmpty) return;
    lines.add('$label: $v');
  }

  addIfPresent('Platform', platform);
  addIfPresent('App', appVersion);
  addIfPresent('Username', username);

  final detail = error.toString().trim();
  lines
    ..add('')
    ..add('Error:')
    ..add(detail.isEmpty ? '(no error message)' : detail);

  return lines.join('\n');
}

/// The short, non-technical sentence shown above the error details.
///
/// Deliberately does not name a recovery path the app cannot offer: there is
/// no SMS fallback, so the honest next step is "send this to us".
const String errorReportGuidance =
    'Something went wrong. Copy the details below and post them in our Discord '
    'and we\'ll help you get set up.';

/// Where copied reports should be posted.
const String gridDiscordInvite = 'https://discord.gg/cJrQXMn6Hk';
