/// Which deletion flow an account should use.
///
/// Grid has three distinct deletion paths and the wrong one produces a
/// misleading error. In particular, passkey-only accounts on the default
/// server have no phone number on file, so routing them through the SMS
/// deactivation flow surfaces "Phone number not found / beta account?" —
/// confusing and wrong. Resolving the route up front keeps the picker in one
/// pure, testable place.
enum AccountDeletionRoute {
  /// Default-server account created via SMS/phone — deactivate via the GAUTH
  /// phone-code flow.
  sms,

  /// Self-hosted / custom homeserver — deactivate directly against the Matrix
  /// deactivate endpoint with the account password.
  customServerPassword,

  /// Default-server passkey-only account — no phone number on file. GAUTH has
  /// no passkey self-deactivation endpoint yet, so send the user to support
  /// rather than down the SMS path.
  passkeyManualSupport,
}

/// Decide how a delete-account request should be handled.
///
/// Mirrors the original inline check (`serverType == 'default'` OR the trimmed
/// homeserver matching the default homeserver) for identifying a default-server
/// account, then splits default-server accounts by whether a phone number is on
/// file so passkey-only accounts no longer fall into the SMS flow.
AccountDeletionRoute resolveAccountDeletionRoute({
  required String? serverType,
  required String? homeserver,
  required String? defaultHomeserver,
  required String? phoneNumber,
}) {
  final isDefaultServer = serverType == 'default' ||
      (homeserver?.trim() == defaultHomeserver?.trim());

  if (!isDefaultServer) {
    return AccountDeletionRoute.customServerPassword;
  }

  final hasPhone = phoneNumber != null && phoneNumber.isNotEmpty;
  return hasPhone
      ? AccountDeletionRoute.sms
      : AccountDeletionRoute.passkeyManualSupport;
}
