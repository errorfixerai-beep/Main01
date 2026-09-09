import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_provider.dart';
import '../services/api_service.dart';
import '../services/push_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/app_brand_background.dart';
import '../providers/language_provider.dart';
import 'username_setup_screen.dart';
import 'dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool isLogin = false; // default: Sign Up screen shows first for new users
  bool loading = false;
  bool googleLoading = false;
  bool obscurePassword = true;
  String? slowServerHint;
  Timer? _slowHintTimer;

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  void _startSlowHintTimer() {
    _slowHintTimer?.cancel();
    _slowHintTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() => slowServerHint = context.tr('waking_up_server_hint'));
      }
    });
  }

  void _clearSlowHint() {
    _slowHintTimer?.cancel();
    if (mounted) setState(() => slowServerHint = null);
  }

  @override
  void dispose() {
    _slowHintTimer?.cancel();
    super.dispose();
  }

  void _goNext(Map<String, dynamic>? user) {
    final username = user?['username'];
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => (username == null || username == '') ? const UsernameSetupScreen() : const DashboardScreen(),
    ));
  }

  Future<void> _submitEmailAuth() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => loading = true);
    _startSlowHintTimer();
    final auth = context.read<AuthProvider>();
    try {
      if (isLogin) {
        await auth.emailLogin(email: _emailCtrl.text.trim(), password: _passwordCtrl.text);
      } else {
        await auth.emailSignup(name: _nameCtrl.text.trim(), email: _emailCtrl.text.trim(), password: _passwordCtrl.text);
      }
      if (!mounted) return;
      PushService.initAfterLogin();
      _goNext(auth.user);
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      _clearSlowHint();
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _submitGoogle() async {
    setState(() => googleLoading = true);
    _startSlowHintTimer();
    final auth = context.read<AuthProvider>();
    try {
      await auth.googleLogin();
      if (!mounted) return;
      PushService.initAfterLogin();
      _goNext(auth.user);
    } catch (e) {
      if (mounted) showApiError(context, e);
    } finally {
      _clearSlowHint();
      if (mounted) setState(() => googleLoading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      showToast(context, context.tr('valid_email_first_error'), isError: true);
      return;
    }
    try {
      await ApiService.instance.forgotPassword(email);
      if (mounted) showToast(context, context.tr('reset_link_sent'), isSuccess: true);
    } catch (e) {
      if (mounted) showApiError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ⚠️ FIX (Boss request): same off-white base + watermark as Splash.
      backgroundColor: const Color(0xFFFAF7FC),
      body: AppBrandBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    SizedBox(
                      width: 84,
                      height: 84,
                      child: Image.asset(
                        'assets/splash.png',
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Icon(Icons.play_arrow_rounded, color: AppColors.purple, size: 40),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(isLogin ? context.tr('welcome_back') : context.tr('create_account'),
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Text(isLogin ? context.tr('sign_in_to_continue') : context.tr('start_scheduling_seconds'),
                        style: TextStyle(color: context.surfaces.textDim)),
                    const SizedBox(height: 26),

                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: googleLoading ? null : _submitGoogle,
                        icon: googleLoading
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : Image.network(
                                'https://developers.google.com/identity/images/g-logo.png',
                                width: 18, height: 18,
                                errorBuilder: (_, __, ___) => const Text('🔵', style: TextStyle(fontSize: 16)),
                              ),
                        label: Text(isLogin ? context.tr('continue_with_google') : context.tr('signup_with_google')),
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Row(children: [
                        Expanded(child: Divider(color: context.surfaces.border)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Text(context.tr('or_continue_with_email'), style: TextStyle(color: context.surfaces.textDim, fontSize: 12.5)),
                        ),
                        Expanded(child: Divider(color: context.surfaces.border)),
                      ]),
                    ),

                    if (!isLogin) ...[
                      _buildLabel(context, context.tr('full_name_label')),
                      TextFormField(
                        controller: _nameCtrl,
                        decoration: InputDecoration(hintText: context.tr('your_full_name_hint')),
                        validator: (v) => (v == null || v.trim().isEmpty) ? context.tr('enter_your_name_error') : null,
                      ),
                      const SizedBox(height: 14),
                    ],

                    _buildLabel(context, context.tr('email_label')),
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(hintText: 'you@example.com'),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return context.tr('enter_your_email_error');
                        if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v.trim())) return context.tr('enter_valid_email_error');
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),

                    _buildLabel(context, context.tr('password_label')),
                    TextFormField(
                      controller: _passwordCtrl,
                      obscureText: obscurePassword,
                      decoration: InputDecoration(
                        hintText: '••••••••',
                        suffixIcon: IconButton(
                          icon: Icon(obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 19),
                          onPressed: () => setState(() => obscurePassword = !obscurePassword),
                        ),
                      ),
                      validator: (v) => (v == null || v.length < 6) ? context.tr('password_min_length_error') : null,
                    ),

                    if (isLogin)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _forgotPassword,
                          child: Text(context.tr('forgot_password'), style: const TextStyle(color: AppColors.purple, fontSize: 13)),
                        ),
                      ),

                    const SizedBox(height: 10),
                    GradientButton(
                      label: isLogin ? context.tr('login_btn') : context.tr('signup_btn'),
                      loading: loading,
                      onPressed: _submitEmailAuth,
                    ),
                    if (slowServerHint != null) ...[
                      const SizedBox(height: 10),
                      Text(slowServerHint!, style: const TextStyle(color: AppColors.purpleLight, fontSize: 12), textAlign: TextAlign.center),
                    ],
                    const SizedBox(height: 16),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(isLogin ? context.tr('no_account_prompt') : context.tr('have_account_prompt'),
                            style: TextStyle(color: context.surfaces.textDim, fontSize: 13)),
                        GestureDetector(
                          onTap: () => setState(() => isLogin = !isLogin),
                          child: Text(isLogin ? context.tr('signup_btn') : context.tr('login_btn'),
                              style: const TextStyle(color: AppColors.purpleLight, fontSize: 13, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(context.tr('terms_privacy_notice'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: context.surfaces.textDim, fontSize: 11.5)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(BuildContext context, String text) => Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(text, style: TextStyle(color: context.surfaces.textDim, fontSize: 13)),
        ),
      );
}