import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:grid_frontend/services/user_service.dart';
import 'package:grid_frontend/styles/tokens.dart';
import 'package:grid_frontend/widgets/grid/grid_button.dart';
import 'package:grid_frontend/widgets/grid/grid_mono.dart';

class SignUpScreen extends StatefulWidget {
  @override
  _SignUpScreenState createState() => _SignUpScreenState();
}

/// Live availability state of the handle in the input.
enum _HandleState { idle, checking, available, taken, invalid }

class _SignUpScreenState extends State<SignUpScreen> with TickerProviderStateMixin {
  late String _homeserver;
  late String _mapsUrl;

  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameFocus = FocusNode();

  bool _isLoading = false;
  String? _errorMessage;

  _HandleState _handleState = _HandleState.idle;
  Timer? _debounce;
  String? _lastCheckedHandle;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  // Allowed handle characters per the redesign helper text:
  // lowercase letters, digits, dot, underscore, hyphen.
  static final RegExp _handleRegex = RegExp(r'^[a-z0-9._-]{3,24}$');

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );

    _fadeController.forward();

    _usernameController.addListener(_onUsernameChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final args = ModalRoute.of(context)?.settings.arguments as Map<String, String>? ?? {};
    _homeserver = args['homeserver'] ?? 'matrix-dev.mygrid.app';
    _mapsUrl = args['mapsUrl'] ?? 'https://example.com/tiles.pmtiles';
  }

  // ── Username field plumbing ───────────────────────────────────────────────

  String get _handle => _usernameController.text.trim().toLowerCase();

  bool get _handleValid => _handleRegex.hasMatch(_handle);

  void _onUsernameChanged() {
    // Keep handle lowercase, strip a leading '@' if pasted.
    final raw = _usernameController.text;
    var sanitized = raw.toLowerCase();
    if (sanitized.startsWith('@')) {
      sanitized = sanitized.substring(1);
    }
    if (sanitized != raw) {
      final selection = _usernameController.selection;
      _usernameController.value = TextEditingValue(
        text: sanitized,
        selection: TextSelection.collapsed(
          offset: sanitized.length.clamp(0, selection.baseOffset.clamp(0, sanitized.length)),
        ),
      );
      return; // listener will fire again with sanitized text
    }

    // While typing, hide the badge and tear down any pending check.
    _debounce?.cancel();
    if (sanitized.isEmpty) {
      setState(() => _handleState = _HandleState.idle);
      return;
    }
    if (!_handleValid) {
      setState(() => _handleState = _HandleState.invalid);
      return;
    }
    setState(() => _handleState = _HandleState.idle);
    _debounce = Timer(const Duration(milliseconds: 500), _checkAvailability);
  }

  Future<void> _checkAvailability() async {
    final handle = _handle;
    if (handle.isEmpty || !_handleValid) return;
    _lastCheckedHandle = handle;

    setState(() => _handleState = _HandleState.checking);

    final userService = context.read<UserService>();
    final fullId = '@$handle:${_homeserver.trim()}';
    bool exists = false;
    try {
      exists = await userService.userExists(fullId);
    } catch (_) {
      // Treat failures as "unknown" — leave the badge hidden rather than lie.
      if (!mounted) return;
      if (_lastCheckedHandle != handle) return;
      setState(() => _handleState = _HandleState.idle);
      return;
    }

    if (!mounted) return;
    // Bail if the user kept typing.
    if (_lastCheckedHandle != handle) return;

    setState(() {
      _handleState = exists ? _HandleState.taken : _HandleState.available;
    });
  }

  // ── Suggestion pills ──────────────────────────────────────────────────────

  List<String> _suggestionsFor(String base) {
    if (base.isEmpty) return const [];
    final cleaned = base.replaceAll(RegExp(r'[^a-z0-9._-]'), '');
    if (cleaned.isEmpty) return const [];
    final rand = Random(cleaned.hashCode);
    final pool = <String>{
      '$cleaned.${rand.nextInt(90) + 10}',
      '${cleaned}_${['hq', 'dev', 'irl', 'log'][rand.nextInt(4)]}',
      '$cleaned${rand.nextInt(9) + 1}',
      cleaned.length > 4 ? cleaned.substring(0, cleaned.length - 1) : '$cleaned.app',
    }..removeWhere((s) => s == cleaned || s.length < 3 || s.length > 24);
    return pool.take(4).toList();
  }

  void _applySuggestion(String s) {
    HapticFeedback.selectionClick();
    _usernameController.value = TextEditingValue(
      text: s,
      selection: TextSelection.collapsed(offset: s.length),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTopBar(),
                      const SizedBox(height: 32),
                      _buildHeadline(),
                      const SizedBox(height: 28),
                      _buildHandleInput(),
                      const SizedBox(height: 10),
                      _buildHelperLine(),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 14),
                        _buildErrorCard(),
                      ],
                      const SizedBox(height: 28),
                      _buildSuggestions(),
                      const SizedBox(height: 28),
                      _buildPasswordInput(),
                    ],
                  ),
                ),
              ),
              _buildBottomBar(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Top bar: back + step counter ──────────────────────────────────────────

  Widget _buildTopBar() {
    return Row(
      children: [
        _BackButton(onPressed: () => Navigator.pop(context)),
        const Spacer(),
        const GridMono('2 / 4', color: GridTokens.text3, size: 11, letterSpacing: 0.12),
      ],
    );
  }

  // ── Headline ──────────────────────────────────────────────────────────────

  Widget _buildHeadline() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pick a handle.',
          style: GoogleFonts.getFont(
            'Geist',
            fontSize: 30,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.025 * 30,
            color: GridTokens.text,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "This is how friends find you. It's the only thing about you the server sees.",
          style: GoogleFonts.getFont(
            'Geist',
            fontSize: 14,
            fontWeight: FontWeight.w400,
            letterSpacing: -0.01,
            color: GridTokens.text2,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  // ── Handle input + availability badge ─────────────────────────────────────

  Widget _buildHandleInput() {
    final hasContent = _handle.isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: GridTokens.surface2,
        borderRadius: BorderRadius.circular(GridTokens.rMd),
        border: Border.all(color: GridTokens.mint, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: GridTokens.mint.withOpacity(0.18),
            blurRadius: 14,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        children: [
          Text(
            '@',
            style: GoogleFonts.getFont(
              'Geist',
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: GridTokens.text3,
              height: 1.0,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              controller: _usernameController,
              focusNode: _usernameFocus,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.none,
              cursorColor: GridTokens.mint,
              cursorWidth: 2,
              style: GoogleFonts.getFont(
                'Geist',
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: GridTokens.text,
                height: 1.0,
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                hintText: hasContent ? null : 'anya.beech',
                hintStyle: GoogleFonts.getFont(
                  'Geist',
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: GridTokens.text3,
                ),
              ),
              onSubmitted: (_) {
                if (_canSubmit) _signUp();
              },
            ),
          ),
          if (_availabilityBadge() != null) ...[
            const SizedBox(width: 8),
            _availabilityBadge()!,
          ],
        ],
      ),
    );
  }

  Widget? _availabilityBadge() {
    switch (_handleState) {
      case _HandleState.available:
        return _Badge(
          color: GridTokens.mint,
          bg: GridTokens.mintSoft,
          icon: Icons.check_rounded,
          label: 'available',
        );
      case _HandleState.taken:
        return _Badge(
          color: GridTokens.danger,
          bg: GridTokens.dangerSoft,
          icon: Icons.close_rounded,
          label: 'taken',
        );
      case _HandleState.checking:
      case _HandleState.idle:
      case _HandleState.invalid:
        return null;
    }
  }

  // ── Helper line: "Lowercase only · 3–24 chars · letters, numbers, . _ -" ──

  Widget _buildHelperLine() {
    final body = GoogleFonts.getFont(
      'Geist',
      fontSize: 12,
      fontWeight: FontWeight.w400,
      color: GridTokens.text3,
      letterSpacing: 0,
    );
    final mono = GoogleFonts.getFont(
      'Geist Mono',
      fontSize: 12,
      fontWeight: FontWeight.w500,
      color: GridTokens.text3,
    );
    return RichText(
      text: TextSpan(
        style: body,
        children: [
          const TextSpan(text: 'Lowercase only  ·  3–24 chars  ·  letters, numbers, '),
          TextSpan(text: '.', style: mono),
          const TextSpan(text: ' '),
          TextSpan(text: '_', style: mono),
          const TextSpan(text: ' '),
          TextSpan(text: '-', style: mono),
        ],
      ),
    );
  }

  // ── Suggestion pills ──────────────────────────────────────────────────────

  Widget _buildSuggestions() {
    final base = _handle.isEmpty ? 'anya' : _handle;
    final suggestions = _suggestionsFor(base);
    if (suggestions.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const GridMono('Or try one of these',
            color: GridTokens.text3, size: 10, letterSpacing: 0.12),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in suggestions) _SuggestionPill(text: s, onTap: () => _applySuggestion(s)),
          ],
        ),
      ],
    );
  }

  // ── Password field — same chrome as the handle input above so the two
  //    fields read as one cohesive form instead of two unrelated cards.

  Widget _buildPasswordInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: GridTokens.surface2,
            borderRadius: BorderRadius.circular(GridTokens.rMd),
            border: Border.all(color: GridTokens.hairline, width: 1),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(
                Icons.lock_outline_rounded,
                size: 18,
                color: GridTokens.text3,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _passwordController,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  cursorColor: GridTokens.mint,
                  cursorWidth: 2,
                  style: GoogleFonts.getFont(
                    'Geist',
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: GridTokens.text,
                    height: 1.0,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                    hintText: 'Password',
                    hintStyle: GoogleFonts.getFont(
                      'Geist',
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: GridTokens.text3,
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "Make sure to remember your password. It can't be recovered.",
          style: GoogleFonts.getFont(
            'Geist',
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: GridTokens.text3,
          ),
        ),
      ],
    );
  }

  // ── Error card ────────────────────────────────────────────────────────────

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: GridTokens.dangerSoft,
        borderRadius: BorderRadius.circular(GridTokens.rSm),
        border: Border.all(color: GridTokens.danger.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: GridTokens.danger, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: GoogleFonts.getFont(
                'Geist',
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: GridTokens.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom bar with primary action + sign-in link ─────────────────────────

  bool get _canSubmit =>
      !_isLoading &&
      _handleValid &&
      _passwordController.text.trim().isNotEmpty &&
      _handleState != _HandleState.taken;

  Widget _buildBottomBar() {
    final label = _handle.isEmpty ? 'Sign up' : 'Sign up as @$_handle';
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      decoration: const BoxDecoration(
        color: GridTokens.surface,
        border: Border(top: BorderSide(color: GridTokens.hairline, width: 1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _isLoading
              ? _buildLoadingButton()
              : GridButton(
                  label: label,
                  onPressed: _canSubmit ? _signUp : null,
                ),
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: () {
                Navigator.pushNamed(
                  context,
                  '/login',
                  arguments: {
                    'homeserver': _homeserver,
                    'mapsUrl': _mapsUrl,
                  },
                );
              },
              child: RichText(
                text: TextSpan(
                  text: 'Already have an account? ',
                  style: GoogleFonts.getFont(
                    'Geist',
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: GridTokens.text2,
                  ),
                  children: [
                    TextSpan(
                      text: 'Sign in',
                      style: GoogleFonts.getFont(
                        'Geist',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: GridTokens.mint,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingButton() {
    return Container(
      height: 52,
      width: double.infinity,
      decoration: BoxDecoration(
        color: GridTokens.mint.withOpacity(0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.center,
      child: const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(
          strokeWidth: 2.4,
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF04201A)),
        ),
      ),
    );
  }

  // ── Sign up flow (logic preserved verbatim) ───────────────────────────────

  Future<void> _signUp() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage = 'Username and password cannot be empty';
        _isLoading = false;
      });
      return;
    }

    final client = Provider.of<Client>(context, listen: false);

    try {
      // Ensure the client is logged out before attempting to register a new user
      if (client.isLogged()) {
        await client.logout();
      }

      await client.checkHomeserver(Uri.https(_homeserver.trim(), ''));

      await _registerUser(client, username, password);
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to sign up: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _registerUser(Client client, String username, String password) async {
    try {
      final response = await client.register(
        kind: AccountKind.user,
        username: username,
        password: password,
        auth: null,
        deviceId: null,
        initialDeviceDisplayName: 'Grid App Device',
        inhibitLogin: false,
        refreshToken: true,
      );

      if (response.accessToken == null || response.userId == null) {
        throw Exception('Access token or user ID is null after registration.');
      }

      await _saveToken(response.accessToken!, response.userId!);

      Navigator.pushReplacementNamed(context, '/main');
    } catch (e) {
      if (e is MatrixException && e.errcode == 'M_FORBIDDEN') {
        await _handleAdditionalAuth(client, username, password, e.session);
      } else {
        setState(() {
          _errorMessage = 'Failed to sign up: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleAdditionalAuth(Client client, String username, String password, String? session) async {
    try {
      final authData = AuthenticationData(
        type: 'm.login.dummy',
        session: session,
      );

      final response = await client.register(
        kind: AccountKind.user,
        username: username,
        password: password,
        auth: authData,
        deviceId: null,
        initialDeviceDisplayName: 'Grid App Device',
        inhibitLogin: false,
        refreshToken: true,
      );

      if (response.accessToken == null || response.userId == null) {
        throw Exception('Access token or user ID is null after registration.');
      }

      await _saveToken(response.accessToken!, response.userId!);

      Navigator.pushReplacementNamed(context, '/main');
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to sign up: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _saveToken(String token, String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token', token);
    await prefs.setString('user_id', userId);

    // Store the custom homeserver URL for restoration
    await prefs.setString('custom_homeserver', _homeserver);
    await prefs.setString('maps_url', _mapsUrl); // Save the map tile URL
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _fadeController.dispose();
    _usernameController.removeListener(_onUsernameChanged);
    _usernameController.dispose();
    _passwordController.dispose();
    _usernameFocus.dispose();
    super.dispose();
  }
}

// ── Tiny private widgets ────────────────────────────────────────────────────

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(GridTokens.rMd),
        child: Ink(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: GridTokens.surface2,
            borderRadius: BorderRadius.circular(GridTokens.rMd),
            border: Border.all(color: GridTokens.hairline, width: 1),
          ),
          child: const Icon(Icons.arrow_back_rounded,
              size: 18, color: GridTokens.text),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.color,
    required this.bg,
    required this.icon,
    required this.label,
  });

  final Color color;
  final Color bg;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.getFont(
              'Geist',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionPill extends StatelessWidget {
  const _SuggestionPill({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: GridTokens.surface2,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: GridTokens.hairline, width: 1),
          ),
          child: Text(
            '@$text',
            style: GoogleFonts.getFont(
              'Geist Mono',
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: GridTokens.text,
              height: 1.0,
            ),
          ),
        ),
      ),
    );
  }
}
