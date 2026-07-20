import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../i18n.dart';
import '../theme.dart';
import '../widgets/gs_logo.dart';

/// Sign in / sign up against the shared Supabase project.
///
/// Three ways in, most-frictionless first:
///  1. Continue with Google / Apple (signInWithOAuth) — no password to
///     remember; user_accounts self-heals in AppState.loadAccount on
///     first entry since there is no DB trigger for it.
///  2. Email + password, with a create-account mode (min 8 chars, same
///     rule as the PWA) and email-confirmation handling.
///  3. Forgot password → resetPasswordForEmail sends a one-tap
///     recovery link; AuthGate shows SetNewPasswordScreen when the
///     link lands back in the app. Simple, but the security model is
///     Supabase's standard one — tokenized, expiring, single-use.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.i18n});
  final I18n i18n;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _signup = false;
  String? _error;
  String? _info;

  /// Where OAuth and recovery links return to: the exact URL the app
  /// is served from (localhost in dev, /growsense/app/ in production).
  /// Both must be in the Supabase Auth redirect allowlist.
  /// Where OAuth and recovery links return to.
  ///  - Web: the exact URL the app is served from (localhost in dev,
  ///    growsense.life/app/ in production).
  ///  - iOS/Android: a custom-scheme deep link that re-opens the app;
  ///    supabase_flutter's built-in deep-link handler completes the session.
  ///    The scheme is registered in ios/Runner/Info.plist (CFBundleURLTypes)
  ///    and android/.../AndroidManifest.xml. Every value here must also be in
  ///    the Supabase Auth → URL Configuration redirect allowlist.
  static const String _nativeRedirect =
      'com.growsense.growsense://login-callback/';
  String? get _redirect =>
      kIsWeb ? Uri.base.toString().split('#').first : _nativeRedirect;

  Future<void> _oauth(OAuthProvider provider) async {
    setState(() {
      _error = null;
      _info = null;
    });
    try {
      await Supabase.instance.client.auth
          .signInWithOAuth(provider, redirectTo: _redirect);
      // Web redirects away; AuthGate picks the session up on return.
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    }
  }

  /// Continue with Apple. On iOS/macOS this must use the NATIVE system
  /// sheet (AuthenticationServices) — Apple's guidelines require it and
  /// the browser-redirect flow is a poor fit. Everywhere else (the web
  /// PWA, Android) we fall back to the OAuth redirect used by Google.
  ///
  /// Native flow: make a random nonce, send its SHA-256 to Apple, and
  /// hand Supabase the returned identity token together with the RAW
  /// nonce so it can verify the hash — the standard replay guard.
  Future<void> _appleSignIn() async {
    final t = widget.i18n.t;
    final useNative = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);
    if (!useNative) return _oauth(OAuthProvider.apple);

    setState(() {
      _error = null;
      _info = null;
    });
    try {
      final rawNonce = _generateNonce();
      final hashedNonce =
          sha256.convert(utf8.encode(rawNonce)).toString();
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );
      final idToken = credential.identityToken;
      if (idToken == null) {
        setState(() => _error = t('flutter.auth.apple_failed',
            'Apple sign-in did not return a token — please try again.'));
        return;
      }
      await Supabase.instance.client.auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
        nonce: rawNonce,
      );
      // AuthGate takes over on the new session; loadAccount self-heals
      // the user_accounts row on first entry.
    } on SignInWithAppleAuthorizationException catch (e) {
      // Tapping "Cancel" on the system sheet isn't an error worth showing.
      if (e.code == AuthorizationErrorCode.canceled) return;
      setState(() => _error = e.message);
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    }
  }

  /// Cryptographically-random URL-safe nonce for Sign in with Apple.
  /// Uses Random.secure() over a fixed charset (each index is a tiny
  /// int, so no web 2^53 / bit-shift hazards).
  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
        length, (_) => charset[random.nextInt(charset.length)]).join();
  }

  Future<void> _submit() async {
    final t = widget.i18n.t;
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = t('flutter.enter_email_password'));
      return;
    }
    if (_signup && password.length < 8) {
      setState(() => _error = t('flutter.auth.password_min',
          'Password must be at least 8 characters'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      final auth = Supabase.instance.client.auth;
      if (_signup) {
        final res = await auth.signUp(
            email: email, password: password, emailRedirectTo: _redirect);
        // Email confirmation on → no session yet; say so instead of
        // silently doing nothing (the PWA learned this the hard way).
        if (res.session == null && mounted) {
          setState(() {
            _signup = false;
            _info = t('flutter.auth.check_inbox',
                'Account created — check your email to confirm, then sign in.');
          });
        }
        // With a session, AuthGate takes over and loadAccount creates
        // the user_accounts profile row.
      } else {
        await auth.signInWithPassword(email: email, password: password);
      }
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgotPassword() async {
    final t = widget.i18n.t;
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() {
        _info = null;
        _error = t('flutter.auth.enter_email_first',
            'Type your email above first, then tap "Forgot password?" again.');
      });
      return;
    }
    setState(() {
      _error = null;
      _info = null;
    });
    try {
      await Supabase.instance.client.auth
          .resetPasswordForEmail(email, redirectTo: _redirect);
      setState(() => _info = t('flutter.auth.reset_sent',
          'Reset link sent — open the email and tap the link to choose a new password.'));
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.i18n.t;
    return Scaffold(
      backgroundColor: GsColors.deepGreen,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 14),
                    child: GsLogoMark(size: 44),
                  ),
                ),
                Text(
                  'GrowSense',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.fraunces(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  t('auth.subtitle', 'Pediatric growth intelligence'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: GsColors.surface,
                    borderRadius: BorderRadius.circular(GsRadius.lg),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Social sign-in: no password to remember ──
                      _SocialButton(
                        onPressed:
                            _busy ? null : () => _oauth(OAuthProvider.google),
                        background: Colors.white,
                        foreground: const Color(0xFF1F1F1F),
                        border: GsColors.border2,
                        icon: const _GoogleG(),
                        label: t('flutter.auth.google',
                            'Continue with Google'),
                      ),
                      // Apple sign-in only where the NATIVE flow works
                      // (signInWithIdToken, iOS/macOS). On web + Android it
                      // would fall back to signInWithOAuth, which needs the
                      // Apple Services ID + .p8 web secret that isn't set up —
                      // so hide it there to avoid a dead-end. Guideline 4.8 is
                      // iOS-app-only; Google + email is fine on web/Play.
                      if (!kIsWeb &&
                          (defaultTargetPlatform == TargetPlatform.iOS ||
                              defaultTargetPlatform ==
                                  TargetPlatform.macOS)) ...[
                        const SizedBox(height: 10),
                        _SocialButton(
                          onPressed: _busy ? null : _appleSignIn,
                          background: Colors.black,
                          foreground: Colors.white,
                          icon: const Icon(Icons.apple,
                              size: 20, color: Colors.white),
                          label:
                              t('flutter.auth.apple', 'Continue with Apple'),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Row(children: [
                        const Expanded(
                            child: Divider(color: GsColors.border2)),
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 10),
                          child: Text(t('flutter.auth.or', 'or'),
                              style: const TextStyle(
                                  fontSize: 11.5, color: GsColors.text3)),
                        ),
                        const Expanded(
                            child: Divider(color: GsColors.border2)),
                      ]),
                      const SizedBox(height: 12),

                      // ── Email + password ─────────────────────────
                      TextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        decoration: InputDecoration(
                            labelText: t('common.email', 'Email')),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _password,
                        obscureText: true,
                        onSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: t('common.password', 'Password'),
                          helperText: _signup
                              ? t('flutter.auth.password_min',
                                  'Password must be at least 8 characters')
                              : null,
                          helperStyle: const TextStyle(
                              fontSize: 10.5, color: GsColors.text3),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!,
                            style: const TextStyle(
                                color: GsColors.flag, fontSize: 13)),
                      ],
                      if (_info != null) ...[
                        const SizedBox(height: 12),
                        Text(_info!,
                            style: const TextStyle(
                                color: GsColors.accentDark,
                                fontSize: 13,
                                height: 1.4)),
                      ],
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _busy ? null : _submit,
                        child: Text(_busy
                            ? (_signup
                                ? t('flutter.auth.creating',
                                    'Creating account…')
                                : t('flutter.signing_in', 'Signing in…'))
                            : (_signup
                                ? t('flutter.auth.create_btn',
                                    'Create account')
                                : t('auth.sign_in_btn', 'Sign in'))),
                      ),
                      const SizedBox(height: 6),
                      // Wrap, not Row — the two links overflow a
                      // 375px viewport in some locales otherwise.
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                      _signup = !_signup;
                                      _error = null;
                                      _info = null;
                                    }),
                            child: Text(
                                _signup
                                    ? t('flutter.auth.have_account',
                                        'Have an account? Sign in')
                                    : t('flutter.auth.no_account',
                                        'New here? Create account'),
                                style: const TextStyle(
                                    fontSize: 11.5,
                                    color: GsColors.accent)),
                          ),
                          if (!_signup)
                            TextButton(
                              onPressed: _busy ? null : _forgotPassword,
                              child: Text(
                                  t('flutter.auth.forgot',
                                      'Forgot password?'),
                                  style: const TextStyle(
                                      fontSize: 11.5,
                                      color: GsColors.text2)),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final entry in supportedLanguages.entries)
                      GestureDetector(
                        onTap: () => widget.i18n.setLanguage(entry.key),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: widget.i18n.code == entry.key
                                ? Colors.white.withValues(alpha: 0.18)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color:
                                    Colors.white.withValues(alpha: 0.28)),
                          ),
                          child: Text(
                            entry.value,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton(
      {required this.onPressed,
      required this.background,
      required this.foreground,
      required this.icon,
      required this.label,
      this.border});
  final VoidCallback? onPressed;
  final Color background;
  final Color foreground;
  final Widget icon;
  final String label;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        elevation: 0,
        side: border != null ? BorderSide(color: border!) : BorderSide.none,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          icon,
          const SizedBox(width: 10),
          Text(label,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// The Google "G" in its four brand colors — text-drawn, no asset.
class _GoogleG extends StatelessWidget {
  const _GoogleG();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(painter: _GoogleGPainter()),
    );
  }
}

class _GoogleGPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 2;
    final rect = Rect.fromCircle(center: c, radius: r);
    const stroke = 3.6;
    void arc(double start, double sweep, Color color) => canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke);
    // Brand-standard quadrants (angles in radians, 0 = 3 o'clock)
    arc(-0.35, -1.22, const Color(0xFFEA4335)); // red — top
    arc(-1.57, -1.22, const Color(0xFFFBBC05)); // yellow — left
    arc(-2.79, -1.22, const Color(0xFF34A853)); // green — bottom
    arc(0.75, -1.05, const Color(0xFF4285F4)); // blue — right
    // Blue crossbar into the center
    canvas.drawLine(
        Offset(c.dx, c.dy),
        Offset(c.dx + r + stroke / 2, c.dy),
        Paint()
          ..color = const Color(0xFF4285F4)
          ..strokeWidth = stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Shown by AuthGate when a password-recovery link lands back in the
/// app (AuthChangeEvent.passwordRecovery). One field, one button —
/// the security lives in Supabase's expiring single-use token.
class SetNewPasswordScreen extends StatefulWidget {
  const SetNewPasswordScreen({super.key, required this.i18n});
  final I18n i18n;

  @override
  State<SetNewPasswordScreen> createState() => _SetNewPasswordScreenState();
}

class _SetNewPasswordScreenState extends State<SetNewPasswordScreen> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    final t = widget.i18n.t;
    if (_password.text.length < 8) {
      setState(() => _error = t('flutter.auth.password_min',
          'Password must be at least 8 characters'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth
          .updateUser(UserAttributes(password: _password.text));
      // USER_UPDATED event moves AuthGate on to the app.
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.i18n.t;
    return Scaffold(
      backgroundColor: GsColors.deepGreen,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: GsColors.surface,
                borderRadius: BorderRadius.circular(GsRadius.lg),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                      t('flutter.auth.new_password_title',
                          'Choose a new password'),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    autofocus: true,
                    onSubmitted: (_) => _save(),
                    decoration: InputDecoration(
                      labelText:
                          t('flutter.auth.new_password', 'New password'),
                      helperText: t('flutter.auth.password_min',
                          'Password must be at least 8 characters'),
                      helperStyle: const TextStyle(
                          fontSize: 10.5, color: GsColors.text3),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(_error!,
                        style: const TextStyle(
                            color: GsColors.flag, fontSize: 13)),
                  ],
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _busy ? null : _save,
                    child: Text(_busy
                        ? t('flutter.saving', 'Saving…')
                        : t('flutter.auth.update_password',
                            'Set new password')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
