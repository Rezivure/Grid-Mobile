/// Honest, actionable user-facing guidance for passkey auth failures.
///
/// SMS verification was deprecated and there is no SMS fallback in the signup
/// or login UI, so the old "Please try SMS verification" copy pointed users at
/// an option that does not exist (GH #285). These helpers return messages that
/// only reference paths a user can actually take: retry, use a different
/// password manager / device authenticator, or reach a human.
///
/// Pure functions — no BuildContext, no I/O — so they are unit-testable.
library;

/// Where to send users who need hands-on help. Keeping this in one place means
/// both messages stay consistent if it ever changes.
const String _supportHint =
    'If it keeps failing, open an issue at github.com/Rezivure/Grid-Mobile or reach out to the team.';

/// Guidance shown when creating a brand-new account with a passkey fails.
String passkeySignupErrorMessage() {
  return 'We couldn\'t create your passkey. Make sure your device or password '
      'manager supports passkeys, then try again. $_supportHint';
}

/// Guidance shown when signing in with an existing passkey fails.
String passkeyLoginErrorMessage() {
  return 'We couldn\'t sign you in with your passkey. Try again, and make sure '
      'you\'re using the same device or password manager you signed up with. '
      '$_supportHint';
}
