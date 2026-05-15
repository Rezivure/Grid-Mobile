import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:passkeys/types.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:grid_frontend/services/passkey_service.dart';
import 'package:grid_frontend/styles/tokens.dart';
import 'package:grid_frontend/widgets/grid/grid_button.dart';
import 'package:grid_frontend/widgets/grid/grid_mono.dart';
import 'package:grid_frontend/widgets/grid/grid_segmented.dart';

class PasskeyManagementScreen extends StatefulWidget {
  const PasskeyManagementScreen({Key? key}) : super(key: key);

  @override
  State<PasskeyManagementScreen> createState() =>
      _PasskeyManagementScreenState();
}

class _PasskeyManagementScreenState extends State<PasskeyManagementScreen> {
  final PasskeyService _passkeyService = PasskeyService();
  List<PasskeyInfo> _passkeys = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPasskeys();
  }

  Future<String?> _getJwt() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('loginToken');
  }

  Future<void> _loadPasskeys() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final jwt = await _getJwt();
      if (jwt == null) {
        setState(() {
          _error = 'Not authenticated';
          _isLoading = false;
        });
        return;
      }

      final passkeys = await _passkeyService.listPasskeys(jwt);
      setState(() {
        _passkeys = passkeys;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Load passkeys error: $e');
      setState(() {
        _error = 'Failed to load passkeys';
        _isLoading = false;
      });
    }
  }

  Future<void> _addPasskey() async {
    try {
      final jwt = await _getJwt();
      if (jwt == null) return;

      setState(() => _isLoading = true);
      await _passkeyService.registerPasskey(jwt);

      _showStyledSnackBar('Passkey added successfully');

      await _loadPasskeys();
    } on ExcludeCredentialsCanNotBeRegisteredException {
      setState(() => _isLoading = false);
      _showStyledSnackBar('A passkey from this device is already registered');
    } on PasskeyAuthCancelledException {
      setState(() => _isLoading = false);
    } catch (e) {
      setState(() => _isLoading = false);
      final message = e.toString().contains('not expected challenge')
          ? 'This passkey provider is not supported. Please use iCloud Keychain.'
          : 'Failed to add passkey';
      _showStyledSnackBar(message, isError: true);
    }
  }

  void _showStyledSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.getFont(
            'Geist',
            color: isError ? Colors.white : const Color(0xFF04201A),
            fontWeight: FontWeight.w600,
          ),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            isError ? GridTokens.danger : GridTokens.mint,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GridTokens.rMd),
        ),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _deletePasskey(PasskeyInfo passkey) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.9,
            ),
            decoration: BoxDecoration(
              color: GridTokens.surface,
              borderRadius: BorderRadius.circular(GridTokens.rXl),
              border: Border.all(color: GridTokens.hairline),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: GridTokens.dangerSoft,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(GridTokens.rXl),
                      topRight: Radius.circular(GridTokens.rXl),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: GridTokens.danger.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(GridTokens.rMd),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.delete_outline,
                          color: GridTokens.danger,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Delete passkey',
                              style: GoogleFonts.getFont(
                                'Geist',
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: GridTokens.text,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "This can't be undone.",
                              style: GoogleFonts.getFont(
                                'Geist',
                                fontSize: 13,
                                color: GridTokens.text2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: GridTokens.surface2,
                          borderRadius:
                              BorderRadius.circular(GridTokens.rMd),
                          border: Border.all(color: GridTokens.hairline),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.warning_amber_rounded,
                              color: GridTokens.amber,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                "You won't be able to use this passkey to sign in anymore.",
                                style: GoogleFonts.getFont(
                                  'Geist',
                                  fontSize: 13,
                                  color: GridTokens.text2,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: GridButton(
                              label: 'Cancel',
                              style: GridButtonStyle.secondary,
                              onPressed: () =>
                                  Navigator.pop(context, false),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: GridButton(
                              label: 'Delete',
                              style: GridButtonStyle.danger,
                              onPressed: () =>
                                  Navigator.pop(context, true),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmed != true) return;

    try {
      final jwt = await _getJwt();
      if (jwt == null) return;

      setState(() => _isLoading = true);
      await _passkeyService.deletePasskey(jwt, passkey.credentialId);
      _showStyledSnackBar('Passkey deleted');
      await _loadPasskeys();
    } catch (e) {
      setState(() => _isLoading = false);
      final message = e.toString().contains('only passkey')
          ? 'Cannot delete your only passkey'
          : 'Failed to delete passkey';
      _showStyledSnackBar(message, isError: true);
    }
  }

  Future<void> _renamePasskey(PasskeyInfo passkey) async {
    final controller = TextEditingController(text: passkey.name ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.9,
            ),
            decoration: BoxDecoration(
              color: GridTokens.surface,
              borderRadius: BorderRadius.circular(GridTokens.rXl),
              border: Border.all(color: GridTokens.hairline),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    color: GridTokens.mintFaint,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(GridTokens.rXl),
                      topRight: Radius.circular(GridTokens.rXl),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: GridTokens.mintSoft,
                          borderRadius: BorderRadius.circular(GridTokens.rMd),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.edit,
                          color: GridTokens.mint,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Rename passkey',
                              style: GoogleFonts.getFont(
                                'Geist',
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: GridTokens.text,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Give this passkey a recognizable name',
                              style: GoogleFonts.getFont(
                                'Geist',
                                fontSize: 13,
                                color: GridTokens.text2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                  child: Column(
                    children: [
                      TextField(
                        controller: controller,
                        autofocus: true,
                        style: GoogleFonts.getFont(
                          'Geist',
                          fontSize: 15,
                          color: GridTokens.text,
                        ),
                        cursorColor: GridTokens.mint,
                        decoration: InputDecoration(
                          hintText: 'e.g. YubiKey, iPhone, Work laptop',
                          hintStyle: GoogleFonts.getFont(
                            'Geist',
                            color: GridTokens.text3,
                            fontSize: 15,
                          ),
                          filled: true,
                          fillColor: GridTokens.surface2,
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(GridTokens.rMd),
                            borderSide:
                                const BorderSide(color: GridTokens.hairline),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(GridTokens.rMd),
                            borderSide:
                                const BorderSide(color: GridTokens.hairline),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(GridTokens.rMd),
                            borderSide: const BorderSide(
                              color: GridTokens.mint,
                              width: 1.5,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                        ),
                        onSubmitted: (value) =>
                            Navigator.pop(context, value.trim()),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: GridButton(
                              label: 'Cancel',
                              style: GridButtonStyle.secondary,
                              onPressed: () => Navigator.pop(context),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: GridButton(
                              label: 'Save',
                              style: GridButtonStyle.primary,
                              onPressed: () => Navigator.pop(
                                context,
                                controller.text.trim(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (name == null || name.isEmpty) return;

    try {
      final jwt = await _getJwt();
      if (jwt == null) return;

      await _passkeyService.renamePasskey(jwt, passkey.credentialId, name);
      await _loadPasskeys();
    } catch (e) {
      _showStyledSnackBar('Failed to rename passkey', isError: true);
    }
  }

  Future<void> _showPasskeyMenu(PasskeyInfo passkey) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Container(
              decoration: BoxDecoration(
                color: GridTokens.surface,
                borderRadius: BorderRadius.circular(GridTokens.rLg),
                border: Border.all(color: GridTokens.hairline),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _menuRow(
                    icon: Icons.edit_outlined,
                    label: 'Rename',
                    onTap: () => Navigator.pop(context, 'rename'),
                  ),
                  const Divider(
                    height: 1,
                    thickness: 1,
                    color: GridTokens.hairline,
                  ),
                  _menuRow(
                    icon: Icons.delete_outline,
                    label: 'Delete',
                    color: GridTokens.danger,
                    onTap: () => Navigator.pop(context, 'delete'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (action == 'rename') {
      await _renamePasskey(passkey);
    } else if (action == 'delete') {
      await _deletePasskey(passkey);
    }
  }

  Widget _menuRow({
    required IconData icon,
    required String label,
    Color? color,
    required VoidCallback onTap,
  }) {
    final fg = color ?? GridTokens.text;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              Icon(icon, size: 20, color: fg),
              const SizedBox(width: 14),
              Text(
                label,
                style: GoogleFonts.getFont(
                  'Geist',
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showRecoveryPhrase() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: GridTokens.surface,
                borderRadius: BorderRadius.circular(GridTokens.rXl),
                border: Border.all(color: GridTokens.hairline),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: GridTokens.mintSoft,
                          borderRadius: BorderRadius.circular(GridTokens.rMd),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.lock_outline,
                          color: GridTokens.mint,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Recovery phrase',
                              style: GoogleFonts.getFont(
                                'Geist',
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: GridTokens.text,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const GridMono(
                              '24 WORDS · STORED OFFLINE',
                              size: 10.5,
                              letterSpacing: 0.12,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: GridTokens.surface2,
                      borderRadius:
                          BorderRadius.circular(GridTokens.rMd),
                      border: Border.all(color: GridTokens.hairline),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: GridTokens.amber,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Recovery phrase reveal is not yet available. Use a registered passkey to sign in.',
                            style: GoogleFonts.getFont(
                              'Geist',
                              fontSize: 13,
                              color: GridTokens.text2,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  GridButton(
                    label: 'Close',
                    style: GridButtonStyle.secondary,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GridTokens.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Text(
          'Passkeys',
          style: GoogleFonts.getFont(
            'Geist',
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: GridTokens.text,
            letterSpacing: -0.01,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: GridTokens.text),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (!_isLoading && _error == null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                icon: const Icon(Icons.add, color: GridTokens.mint),
                onPressed: _addPasskey,
              ),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  color: GridTokens.mint,
                ),
              )
            : _error != null
                ? _buildErrorState()
                : _buildContent(),
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
                color: GridTokens.dangerSoft,
                borderRadius: BorderRadius.circular(GridTokens.rLg),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.error_outline,
                size: 28,
                color: GridTokens.danger,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: GoogleFonts.getFont(
                'Geist',
                fontSize: 15,
                color: GridTokens.text2,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            GridButton(
              label: 'Retry',
              expand: false,
              onPressed: _loadPasskeys,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadPasskeys,
            color: GridTokens.mint,
            backgroundColor: GridTokens.surface,
            strokeWidth: 2.5,
            displacement: 20,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                _buildInfoCard(),
                const SizedBox(height: 8),
                GridSectionHeader(
                  text: 'YOUR PASSKEYS',
                  trailing: _passkeys.isEmpty
                      ? null
                      : GridMono(
                          '${_passkeys.length} ACTIVE',
                          color: GridTokens.text3,
                          size: 10.5,
                          letterSpacing: 0.12,
                        ),
                ),
                if (_passkeys.isEmpty)
                  _buildEmptyState()
                else
                  ..._passkeys.asMap().entries.map((entry) {
                    final isFirst = entry.key == 0;
                    return Padding(
                      padding: EdgeInsets.only(
                        top: entry.key == 0 ? 4 : 10,
                      ),
                      child: _buildPasskeyCard(
                        entry.value,
                        isCurrentDevice: isFirst,
                      ),
                    );
                  }),
                const SizedBox(height: 8),
                const GridSectionHeader(text: 'BACKUP'),
                _buildRecoveryRow(),
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: GridButton(
            label: 'Add a passkey',
            icon: Icons.add,
            onPressed: _addPasskey,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: GridTokens.mintFaint,
        borderRadius: BorderRadius.circular(GridTokens.rLg),
        border: Border.all(color: GridTokens.mintSoft),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.shield_outlined,
            color: GridTokens.mint,
            size: 18,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Sign in with Face ID, Touch ID, or device PIN instead of SMS codes — phishing-proof and faster.',
              style: GoogleFonts.getFont(
                'Geist',
                fontSize: 13,
                color: GridTokens.text2,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: GridTokens.surface,
        borderRadius: BorderRadius.circular(GridTokens.rLg),
        border: Border.all(color: GridTokens.hairline),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: GridTokens.mintFaint,
              borderRadius: BorderRadius.circular(GridTokens.rLg),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.fingerprint,
              size: 28,
              color: GridTokens.mint,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'No passkeys yet',
            style: GoogleFonts.getFont(
              'Geist',
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: GridTokens.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Add a passkey for faster, more secure login.',
            style: GoogleFonts.getFont(
              'Geist',
              fontSize: 13,
              color: GridTokens.text2,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPasskeyCard(
    PasskeyInfo passkey, {
    required bool isCurrentDevice,
  }) {
    final name = passkey.name ??
        (passkey.backedUp ? 'Synced passkey' : 'Security key');
    final typeLabel = passkey.backedUp ? 'SYNCED' : 'HARDWARE';
    final tileBg =
        passkey.backedUp ? GridTokens.mintFaint : GridTokens.amberSoft;
    final iconColor =
        passkey.backedUp ? GridTokens.mint : GridTokens.amber;
    final icon = passkey.backedUp
        ? Icons.lock_outline_rounded
        : Icons.usb_rounded;

    final addedText = _formatAdded(passkey.createdAt);
    final lastUsedText = _formatLastUsed(passkey.lastUsedAt);
    final metaText = lastUsedText != null
        ? '$addedText · $lastUsedText'
        : addedText;

    final isHighlight = isCurrentDevice;
    final cardBg = isHighlight ? GridTokens.mintFaint : GridTokens.surface;
    final cardBorder = isHighlight
        ? Border.all(color: GridTokens.mintSoft)
        : Border.all(color: GridTokens.hairline);

    return Dismissible(
      key: Key(passkey.credentialId),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: GridTokens.dangerSoft,
          borderRadius: BorderRadius.circular(GridTokens.rLg),
        ),
        child: const Icon(Icons.delete_outline, color: GridTokens.danger),
      ),
      confirmDismiss: (_) async {
        _deletePasskey(passkey);
        return false;
      },
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _renamePasskey(passkey),
          borderRadius: BorderRadius.circular(GridTokens.rLg),
          child: Ink(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(GridTokens.rLg),
              border: cardBorder,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: tileBg,
                      borderRadius: BorderRadius.circular(GridTokens.rMd),
                    ),
                    alignment: Alignment.center,
                    child: Icon(icon, color: iconColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 160),
                              child: Text(
                                name,
                                style: GoogleFonts.getFont(
                                  'Geist',
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: GridTokens.text,
                                  letterSpacing: -0.01,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                            _MonoChip(
                              label: typeLabel,
                              bg: passkey.backedUp
                                  ? GridTokens.mintSoft
                                  : GridTokens.amberSoft,
                              fg: passkey.backedUp
                                  ? GridTokens.mint
                                  : GridTokens.amber,
                            ),
                            if (isCurrentDevice)
                              const _MonoChip(
                                label: 'THIS DEVICE',
                                bg: GridTokens.surface2,
                                fg: GridTokens.text2,
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        GridMono(
                          metaText,
                          size: 10.5,
                          color: GridTokens.text3,
                          letterSpacing: 0.08,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => _showPasskeyMenu(passkey),
                    icon: const Icon(
                      Icons.more_horiz,
                      color: GridTokens.text2,
                      size: 20,
                    ),
                    splashRadius: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecoveryRow() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _showRecoveryPhrase,
        borderRadius: BorderRadius.circular(GridTokens.rLg),
        child: Ink(
          decoration: BoxDecoration(
            color: GridTokens.surface,
            borderRadius: BorderRadius.circular(GridTokens.rLg),
            border: Border.all(color: GridTokens.hairline),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: GridTokens.surface2,
                    borderRadius: BorderRadius.circular(GridTokens.rMd),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.menu_book_outlined,
                    color: GridTokens.text2,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Recovery phrase',
                        style: GoogleFonts.getFont(
                          'Geist',
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: GridTokens.text,
                          letterSpacing: -0.01,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '24 words · stored offline',
                        style: GoogleFonts.getFont(
                          'Geist',
                          fontSize: 13,
                          color: GridTokens.text2,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: GridTokens.text3,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatAdded(DateTime? dt) {
    if (dt == null) return 'ADDED —';
    const months = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC',
    ];
    return 'ADDED ${months[dt.month - 1]} ${dt.day}';
  }

  String? _formatLastUsed(DateTime? dt) {
    if (dt == null) return null;
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'LAST USED JUST NOW';
    if (diff.inMinutes < 60) {
      return 'LAST USED ${diff.inMinutes} MIN AGO';
    }
    if (diff.inHours < 24) {
      return 'LAST USED ${diff.inHours} HR AGO';
    }
    if (diff.inDays == 1) return 'LAST USED YESTERDAY';
    if (diff.inDays < 7) return 'LAST USED ${diff.inDays} DAYS AGO';
    if (diff.inDays < 30) {
      final weeks = (diff.inDays / 7).floor();
      return 'LAST USED $weeks ${weeks == 1 ? 'WEEK' : 'WEEKS'} AGO';
    }
    if (diff.inDays < 365) {
      final months = (diff.inDays / 30).floor();
      return 'LAST USED $months ${months == 1 ? 'MONTH' : 'MONTHS'} AGO';
    }
    final years = (diff.inDays / 365).floor();
    return 'LAST USED $years ${years == 1 ? 'YEAR' : 'YEARS'} AGO';
  }
}

class _MonoChip extends StatelessWidget {
  const _MonoChip({
    required this.label,
    required this.bg,
    required this.fg,
  });

  final String label;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: GridMono(
        label,
        size: 9.5,
        color: fg,
        letterSpacing: 0.12,
      ),
    );
  }
}
