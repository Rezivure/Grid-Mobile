import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:grid_frontend/services/in_app_notifier.dart';
import 'package:grid_frontend/services/password_auth_service.dart';
import 'package:grid_frontend/styles/grid_colors.dart';
import 'package:grid_frontend/styles/tokens.dart';
import 'package:grid_frontend/utilities/utils.dart';
import 'package:grid_frontend/widgets/grid/grid_button.dart';

/// Set or change the account password.
///
/// A full screen rather than a dialog: it needs current + new + confirm, the
/// no-recovery warning and its acknowledgement checkbox, and there is no
/// version of that which fits comfortably in a modal.
///
/// Deliberately does not reuse settings_page's `_buildPasswordConfirmationDialog`
/// — that one is hard-wired to the account-deletion flow and only applies to
/// custom-homeserver accounts.
class PasswordSetupScreen extends StatefulWidget {
  const PasswordSetupScreen({super.key});

  @override
  State<PasswordSetupScreen> createState() => _PasswordSetupScreenState();
}

class _PasswordSetupScreenState extends State<PasswordSetupScreen> {
  final PasswordAuthService _service = PasswordAuthService();

  final TextEditingController _currentPasswordController =
      TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  String? _loadError;

  /// Whether the account already has a password. Drives both the copy and
  /// whether `current_password` is required: a passkey-only user has nothing
  /// to prove ownership with except the JWT they already hold.
  bool _hasPassword = false;
  bool _hasPasskey = false;

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _acknowledgedNoRecovery = false;

  /// Inline error for a wrong current password or a server policy rejection.
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<String?> _getJwt() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('loginToken');
  }

  Future<void> _loadStatus() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final jwt = await _getJwt();
      if (jwt == null) {
        setState(() {
          _loadError = 'Not authenticated';
          _isLoading = false;
        });
        return;
      }

      final status = await _service.status(jwt);
      if (!mounted) return;
      setState(() {
        _hasPassword = status.hasPassword;
        _hasPasskey = status.hasPasskey;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Failed to load password settings';
        _isLoading = false;
      });
    }
  }

  Future<void> _submit() async {
    // Never trimmed. See passwordValidationError in utilities/utils.dart.
    final newPassword = _newPasswordController.text;
    final currentPassword = _currentPasswordController.text;

    setState(() {
      _isSaving = true;
      _submitError = null;
    });

    try {
      final jwt = await _getJwt();
      if (jwt == null) {
        setState(() {
          _submitError = 'Not authenticated. Sign out and back in, then retry.';
          _isSaving = false;
        });
        return;
      }

      await _service.setPassword(
        jwt: jwt,
        newPassword: newPassword,
        currentPassword: _hasPassword ? currentPassword : null,
      );

      if (!mounted) return;
      InAppNotifier.instance.show(
        title: _hasPassword ? 'Password changed' : 'Password set',
        message: 'Save it in your password manager.',
        variant: InAppNotificationVariant.success,
      );
      Navigator.pop(context, true);
    } on InvalidCredentialsException {
      if (!mounted) return;
      setState(() {
        _submitError = 'That current password is not right.';
        _isSaving = false;
      });
    } on WeakPasswordException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitError = e.message;
        _isSaving = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitError = 'Could not save your password. Please try again.';
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.gridColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Text(
          _hasPassword ? 'Change password' : 'Set a password',
          style: GoogleFonts.getFont(
            'Geist',
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: context.gridColors.text,
            letterSpacing: -0.01,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.gridColors.text),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        top: false,
        child: _isLoading
            ? Center(
                child: CircularProgressIndicator(color: context.gridColors.mint),
              )
            : _loadError != null
                ? _buildErrorState()
                : _buildForm(),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: context.gridColors.dangerSoft,
                borderRadius: BorderRadius.circular(GridTokens.rLg),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.error_outline,
                size: 28,
                color: context.gridColors.danger,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _loadError!,
              style: GoogleFonts.getFont(
                'Geist',
                fontSize: 15,
                color: context.gridColors.text2,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            GridButton(
              label: 'Retry',
              expand: false,
              onPressed: _loadStatus,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    final newPassword = _newPasswordController.text;
    final confirmation = _confirmPasswordController.text;

    final policyError =
        newPassword.isEmpty ? null : passwordValidationError(newPassword);
    final matchError = confirmation.isEmpty
        ? null
        : passwordConfirmationError(newPassword, confirmation);

    final canSubmit = !_isSaving &&
        passwordValidationError(newPassword) == null &&
        passwordConfirmationError(newPassword, confirmation) == null &&
        _acknowledgedNoRecovery &&
        (!_hasPassword || _currentPasswordController.text.isNotEmpty);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _hasPassword
                ? 'Your password is a second way into your account, alongside any passkeys you have.'
                : 'Add a password so you can sign in even without a passkey.',
            style: GoogleFonts.getFont(
              'Geist',
              fontSize: 14,
              color: context.gridColors.text2,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 24),

          if (_hasPassword) ...[
            _buildField(
              controller: _currentPasswordController,
              label: 'Current password',
              obscure: _obscureCurrent,
              onToggle: () => setState(() => _obscureCurrent = !_obscureCurrent),
            ),
            const SizedBox(height: 16),
          ],

          _buildField(
            controller: _newPasswordController,
            label: 'New password',
            hint: 'At least $kPasswordMinLength characters',
            obscure: _obscureNew,
            onToggle: () => setState(() => _obscureNew = !_obscureNew),
          ),
          if (policyError != null) ...[
            const SizedBox(height: 10),
            _buildInlineMessage(policyError),
          ],

          const SizedBox(height: 16),

          _buildField(
            controller: _confirmPasswordController,
            label: 'Confirm new password',
            obscure: _obscureConfirm,
            onToggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
          ),
          if (matchError != null) ...[
            const SizedBox(height: 10),
            _buildInlineMessage(matchError),
          ],

          const SizedBox(height: 24),

          _buildNoRecoveryWarning(),

          const SizedBox(height: 12),

          InkWell(
            onTap: () => setState(
                () => _acknowledgedNoRecovery = !_acknowledgedNoRecovery),
            borderRadius: BorderRadius.circular(GridTokens.rSm),
            child: Row(
              children: [
                Checkbox(
                  value: _acknowledgedNoRecovery,
                  activeColor: context.gridColors.mint,
                  checkColor: Colors.black,
                  onChanged: (value) =>
                      setState(() => _acknowledgedNoRecovery = value ?? false),
                ),
                Expanded(
                  child: Text(
                    "I understand my password can't be recovered",
                    style: GoogleFonts.getFont(
                      'Geist',
                      fontSize: 14,
                      color: context.gridColors.text,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (!_hasPasskey) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.gridColors.surface2,
                borderRadius: BorderRadius.circular(GridTokens.rMd),
                border: Border.all(color: context.gridColors.hairline),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    size: 18,
                    color: context.gridColors.mint,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Tip: add a passkey too. If you lose one, the other still gets you in.',
                      style: GoogleFonts.getFont(
                        'Geist',
                        fontSize: 13,
                        color: context.gridColors.text2,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (_submitError != null) ...[
            const SizedBox(height: 16),
            _buildInlineMessage(_submitError!),
          ],

          const SizedBox(height: 24),

          GridButton(
            label: _hasPassword ? 'Change password' : 'Set password',
            onPressed: canSubmit ? _submit : null,
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    String? hint,
    required bool obscure,
    required VoidCallback onToggle,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: false,
      onChanged: (_) => setState(() => _submitError = null),
      style: GoogleFonts.getFont(
        'Geist',
        fontSize: 15,
        color: context.gridColors.text,
      ),
      cursorColor: context.gridColors.mint,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.getFont(
          'Geist',
          color: context.gridColors.text2,
          fontSize: 14,
        ),
        hintText: hint,
        hintStyle: GoogleFonts.getFont(
          'Geist',
          color: context.gridColors.text3,
          fontSize: 15,
        ),
        filled: true,
        fillColor: context.gridColors.surface2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(GridTokens.rMd),
          borderSide: BorderSide(color: context.gridColors.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(GridTokens.rMd),
          borderSide: BorderSide(color: context.gridColors.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(GridTokens.rMd),
          borderSide: BorderSide(color: context.gridColors.mint, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        suffixIcon: IconButton(
          icon: Icon(
            obscure
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            color: context.gridColors.text3,
          ),
          onPressed: onToggle,
        ),
      ),
    );
  }

  Widget _buildInlineMessage(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: context.gridColors.dangerSoft,
        borderRadius: BorderRadius.circular(GridTokens.rSm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 16, color: context.gridColors.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.getFont(
                'Geist',
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: context.gridColors.danger,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoRecoveryWarning() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.gridColors.dangerSoft,
        borderRadius: BorderRadius.circular(GridTokens.rMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 20,
                color: context.gridColors.danger,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'There is no password reset.',
                  style: GoogleFonts.getFont(
                    'Geist',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: context.gridColors.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            "Grid never collects your email or phone number, so we have no way "
            "to verify it's you — and no way to reset this password. If you "
            "forget it and you don't have a passkey, your account and "
            "everything in it is gone for good.",
            style: GoogleFonts.getFont(
              'Geist',
              fontSize: 13,
              color: context.gridColors.text2,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Save it in your password manager before you continue.',
            style: GoogleFonts.getFont(
              'Geist',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.gridColors.text,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
