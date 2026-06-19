import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../config.dart';
import '../mutations.dart';
import '../providers.dart';
import '../theme.dart';

const _kDuration = Duration(milliseconds: 380);
const _kCurve = Curves.easeInOut;

// Page indices
const _kPageWelcome = 0;
const _kPageServer = 1;
const _kPageAuth = 2;

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  late final PageController _page;

  // Auth mode
  bool _isSignIn = true;

  // Server page
  final _serverCtrl = TextEditingController();
  bool _serverError = false;

  // Auth fields
  final _authFormKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _displayNameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _inviteCtrl = TextEditingController();

  // Inline server edit on auth page
  bool _editingServerInline = false;
  final _serverInlineCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final start = AppConfig.isConfigured ? _kPageAuth : _kPageWelcome;
    _page = PageController(initialPage: start);
    if (AppConfig.isConfigured) {
      _serverInlineCtrl.text = _stripScheme(AppConfig.serverUrl);
    }
    _serverCtrl.addListener(() => setState(() => _serverError = false));
  }

  @override
  void dispose() {
    _page.dispose();
    _serverCtrl.dispose();
    _usernameCtrl.dispose();
    _displayNameCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _inviteCtrl.dispose();
    _serverInlineCtrl.dispose();
    super.dispose();
  }

  String _stripScheme(String url) =>
      url.replaceAll(RegExp(r'^https?://'), '');

  void _goTo(int page) => _page.animateToPage(
        page,
        duration: _kDuration,
        curve: _kCurve,
      );

  void _goToAuth({bool signIn = true}) {
    setState(() => _isSignIn = signIn);
    _goTo(_kPageAuth);
  }

  Future<void> _saveServer(String raw) async {
    if (raw.trim().isEmpty) {
      setState(() => _serverError = true);
      return;
    }
    await AppConfig.setServerUrl(raw.trim());
    _serverInlineCtrl.text = _stripScheme(AppConfig.serverUrl);
  }

  Future<void> _submitAuth() async {
    final pending = _isSignIn
        ? ref.read(loginMutation).isPending
        : ref.read(registerMutation).isPending;
    if (pending) return;
    if (!AppConfig.isConfigured) return;
    if (!(_authFormKey.currentState?.validate() ?? false)) return;

    if (_isSignIn) {
      loginMutation.run(ref, (tsx) async {
        return tsx.get(authProvider.notifier).login(
              _usernameCtrl.text.trim(),
              _passwordCtrl.text,
            );
      });
    } else {
      registerMutation.run(ref, (tsx) async {
        return tsx.get(authProvider.notifier).register(
              _usernameCtrl.text.trim(),
              _displayNameCtrl.text.trim(),
              _passwordCtrl.text,
              inviteCode: _inviteCtrl.text.trim().isEmpty
                  ? null
                  : _inviteCtrl.text.trim(),
            );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageView(
      controller: _page,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _WelcomePage(
          onGetStarted: () {
            setState(() => _isSignIn = false);
            _goTo(_kPageServer);
          },
          onSignIn: () {
            setState(() => _isSignIn = true);
            _goTo(_kPageServer);
          },
        ),
        _ServerPage(
          controller: _serverCtrl,
          hasError: _serverError,
          onBack: () => _goTo(_kPageWelcome),
          onContinue: () async {
            if (_serverCtrl.text.trim().isEmpty) {
              setState(() => _serverError = true);
              return;
            }
            await _saveServer(_serverCtrl.text);
            if (mounted) _goToAuth(signIn: _isSignIn);
          },
        ),
        _AuthPage(
          isSignIn: _isSignIn,
          authFormKey: _authFormKey,
          usernameCtrl: _usernameCtrl,
          displayNameCtrl: _displayNameCtrl,
          passwordCtrl: _passwordCtrl,
          confirmCtrl: _confirmCtrl,
          inviteCtrl: _inviteCtrl,
          serverInlineCtrl: _serverInlineCtrl,
          editingServerInline: _editingServerInline,
          canGoBack: !AppConfig.isConfigured ||
              (_page.hasClients &&
                  (_page.page ?? _kPageAuth).round() > _kPageWelcome),
          onToggleMode: (v) => setState(() {
            _isSignIn = v;
            _authFormKey.currentState?.reset();
          }),
          onSubmit: _submitAuth,
          onTapServer: () => setState(
              () => _editingServerInline = !_editingServerInline),
          onSaveServerInline: () async {
            await _saveServer(_serverInlineCtrl.text);
            setState(() => _editingServerInline = false);
          },
          onBack: AppConfig.isConfigured
              ? null
              : () => _goTo(_kPageServer),
        ),
      ],
    );
  }
}

// ─── Welcome ─────────────────────────────────────────────────────────────────

class _WelcomePage extends StatelessWidget {
  final VoidCallback onGetStarted;
  final VoidCallback onSignIn;

  const _WelcomePage({required this.onGetStarted, required this.onSignIn});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF08080F),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 44),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 3),
              Center(
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: PointColors.accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Image.asset(
                      'assets/icon/app_icon.png',
                      width: 52,
                      height: 52,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Point',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 52,
                  fontWeight: FontWeight.w900,
                  color: PointColors.accent,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Share where you are.\nOnly with who you choose.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  color: Color(0xFF8888A0),
                  height: 1.55,
                ),
              ),
              const Spacer(flex: 4),
              SizedBox(
                height: 54,
                child: ElevatedButton(
                  onPressed: onGetStarted,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: PointColors.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Get Started',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: onSignIn,
                child: const Text(
                  'Already have an account? Sign in',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF666688),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Server ───────────────────────────────────────────────────────────────────

class _ServerPage extends StatelessWidget {
  final TextEditingController controller;
  final bool hasError;
  final VoidCallback onBack;
  final VoidCallback onContinue;

  const _ServerPage({
    required this.controller,
    required this.hasError,
    required this.onBack,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF08080F),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Back
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                  color: const Color(0xFF8888A0),
                  onPressed: onBack,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 44),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Spacer(flex: 1),
                    const Text(
                      'Connect your\nserver',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        height: 1.2,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Point is self-hosted. Enter your server address to continue.',
                      style: TextStyle(
                        fontSize: 15,
                        color: Color(0xFF8888A0),
                        height: 1.5,
                      ),
                    ),
                    const Spacer(flex: 1),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.go,
                      onSubmitted: (_) => onContinue(),
                      autocorrect: false,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        hintText: 'point.example.com',
                        hintStyle: const TextStyle(
                          color: Color(0xFF44445A),
                          fontSize: 16,
                        ),
                        prefixIcon: const Icon(
                          Icons.dns_rounded,
                          color: Color(0xFF44445A),
                          size: 18,
                        ),
                        filled: true,
                        fillColor: const Color(0xFF14141E),
                        errorText: hasError ? 'Enter a server address' : null,
                        errorStyle:
                            const TextStyle(color: PointColors.danger),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: Color(0xFF1E1E2E),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: PointColors.accent,
                            width: 1.5,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 18,
                        ),
                      ),
                    ),
                    const Spacer(flex: 3),
                    SizedBox(
                      height: 54,
                      child: ElevatedButton(
                        onPressed: onContinue,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: PointColors.accent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Continue',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(width: 6),
                            Icon(Icons.arrow_forward_rounded, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Auth ─────────────────────────────────────────────────────────────────────

class _AuthPage extends ConsumerWidget {
  final bool isSignIn;
  final GlobalKey<FormState> authFormKey;
  final TextEditingController usernameCtrl;
  final TextEditingController displayNameCtrl;
  final TextEditingController passwordCtrl;
  final TextEditingController confirmCtrl;
  final TextEditingController inviteCtrl;
  final TextEditingController serverInlineCtrl;
  final bool editingServerInline;
  final bool canGoBack;
  final ValueChanged<bool> onToggleMode;
  final VoidCallback onSubmit;
  final VoidCallback onTapServer;
  final VoidCallback onSaveServerInline;
  final VoidCallback? onBack;

  const _AuthPage({
    required this.isSignIn,
    required this.authFormKey,
    required this.usernameCtrl,
    required this.displayNameCtrl,
    required this.passwordCtrl,
    required this.confirmCtrl,
    required this.inviteCtrl,
    required this.serverInlineCtrl,
    required this.editingServerInline,
    required this.canGoBack,
    required this.onToggleMode,
    required this.onSubmit,
    required this.onTapServer,
    required this.onSaveServerInline,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loginState = ref.watch(loginMutation);
    final registerState = ref.watch(registerMutation);
    final auth = ref.watch(authProvider);
    final submitting = loginState.isPending || registerState.isPending;
    final mutationError = switch (isSignIn ? loginState : registerState) {
      MutationError(:final error) => error.toString(),
      _ => null,
    };
    final errorText = mutationError ?? auth.error;

    return Scaffold(
      backgroundColor: context.pageBg,
      body: SafeArea(
        child: Column(
          children: [
            // Back button row
            if (onBack != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 20),
                    color: context.secondaryText,
                    onPressed: onBack,
                  ),
                ),
              )
            else
              const SizedBox(height: 16),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),

                    // Pill toggle
                    Container(
                      height: 46,
                      decoration: BoxDecoration(
                        color: context.subtleBg,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Stack(
                        children: [
                          AnimatedPositioned(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeInOut,
                            left: isSignIn ? 4 : null,
                            right: isSignIn ? null : 4,
                            top: 4,
                            bottom: 4,
                            width: (MediaQuery.sizeOf(context).width - 48 - 8) / 2,
                            child: Container(
                              decoration: BoxDecoration(
                                color: context.cardBg,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => onToggleMode(true),
                                  behavior: HitTestBehavior.opaque,
                                  child: Center(
                                    child: Text(
                                      'Sign In',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: isSignIn
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: isSignIn
                                            ? context.primaryText
                                            : context.secondaryText,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => onToggleMode(false),
                                  behavior: HitTestBehavior.opaque,
                                  child: Center(
                                    child: Text(
                                      'Create Account',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: !isSignIn
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: !isSignIn
                                            ? context.primaryText
                                            : context.secondaryText,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 28),

                    // Form — AnimatedSize smoothly handles height change
                    Form(
                      key: authFormKey,
                      child: AnimatedSize(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeInOut,
                        alignment: Alignment.topCenter,
                        child: Column(
                          key: ValueKey(isSignIn),
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _field(
                              context,
                              controller: usernameCtrl,
                              hint: 'Username',
                              action: TextInputAction.next,
                              validator: (v) {
                                if (v == null || v.trim().length < 3) {
                                  return 'At least 3 characters';
                                }
                                return null;
                              },
                            ),
                            if (!isSignIn) ...[
                              const SizedBox(height: 12),
                              _field(
                                context,
                                controller: displayNameCtrl,
                                hint: 'Display Name',
                                action: TextInputAction.next,
                              ),
                            ],
                            const SizedBox(height: 12),
                            _field(
                              context,
                              controller: passwordCtrl,
                              hint: 'Password',
                              obscure: true,
                              action: isSignIn
                                  ? TextInputAction.done
                                  : TextInputAction.next,
                              onSubmitted:
                                  isSignIn ? (_) => onSubmit() : null,
                              validator: (v) {
                                if (v == null || v.length < 8) {
                                  return 'At least 8 characters';
                                }
                                return null;
                              },
                            ),
                            if (!isSignIn) ...[
                              const SizedBox(height: 12),
                              _field(
                                context,
                                controller: confirmCtrl,
                                hint: 'Confirm Password',
                                obscure: true,
                                action: TextInputAction.next,
                                validator: (v) {
                                  if (v != passwordCtrl.text) {
                                    return 'Passwords do not match';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              _field(
                                context,
                                controller: inviteCtrl,
                                hint: 'Invite Code (optional)',
                                action: TextInputAction.done,
                                onSubmitted: (_) => onSubmit(),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Error
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      child: errorText != null
                          ? Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                errorText,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: PointColors.danger,
                                  fontSize: 13,
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),

                    const SizedBox(height: 12),

                    // Submit
                    SizedBox(
                      height: 54,
                      child: ElevatedButton(
                        onPressed: submitting ? null : onSubmit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: PointColors.accent,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              PointColors.accent.withValues(alpha: 0.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        child: submitting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                isSignIn ? 'Sign In' : 'Create Account',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Server chip + inline edit
                    GestureDetector(
                      onTap: onTapServer,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: PointColors.accent
                              .withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.dns_rounded,
                                size: 13, color: PointColors.accent),
                            const SizedBox(width: 6),
                            Text(
                              AppConfig.isConfigured
                                  ? _stripScheme(AppConfig.serverUrl)
                                  : 'No server configured',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: PointColors.accent,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              editingServerInline ? 'cancel' : 'change',
                              style: TextStyle(
                                fontSize: 12,
                                color: context.secondaryText,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    AnimatedSize(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      child: editingServerInline
                          ? Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: serverInlineCtrl,
                                      autofocus: true,
                                      keyboardType: TextInputType.url,
                                      textInputAction: TextInputAction.done,
                                      onSubmitted: (_) =>
                                          onSaveServerInline(),
                                      autocorrect: false,
                                      style: TextStyle(
                                          fontSize: 14,
                                          color: context.primaryText),
                                      decoration: InputDecoration(
                                        hintText: 'point.example.com',
                                        hintStyle: TextStyle(
                                            color: context.hintText,
                                            fontSize: 14),
                                        filled: true,
                                        fillColor: context.cardBg,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 12),
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          borderSide: BorderSide(
                                              color: context.inputBorder),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          borderSide: BorderSide(
                                              color: context.inputBorder),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          borderSide: const BorderSide(
                                              color: PointColors.accent,
                                              width: 1.5),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: onSaveServerInline,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 12),
                                      decoration: BoxDecoration(
                                        color: PointColors.accent,
                                        borderRadius:
                                            BorderRadius.circular(10),
                                      ),
                                      child: const Text(
                                        'Save',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _stripScheme(String url) =>
      url.replaceAll(RegExp(r'^https?://'), '');

  Widget _field(
    BuildContext context, {
    required TextEditingController controller,
    required String hint,
    bool obscure = false,
    TextInputAction? action,
    ValueChanged<String>? onSubmitted,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      textInputAction: action,
      onFieldSubmitted: onSubmitted,
      validator: validator,
      autocorrect: false,
      style: TextStyle(fontSize: 15, color: context.primaryText),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: context.hintText, fontSize: 15),
        filled: true,
        fillColor: context.cardBg,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: context.inputBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: context.inputBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: PointColors.accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: PointColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: PointColors.danger, width: 1.5),
        ),
      ),
    );
  }
}
