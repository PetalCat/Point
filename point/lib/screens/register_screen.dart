import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../config.dart';
import '../mutations.dart';
import '../providers.dart';
import '../theme.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _inviteCodeController = TextEditingController();
  final _serverUrlController = TextEditingController();
  bool _editingServer = false;

  @override
  void initState() {
    super.initState();
    if (AppConfig.isConfigured) {
      _serverUrlController.text = AppConfig.serverUrl.replaceAll(
        RegExp(r'^https?://'),
        '',
      );
    }
    _editingServer = !AppConfig.isConfigured;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _displayNameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _inviteCodeController.dispose();
    _serverUrlController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final register = ref.read(registerMutation);
    if (register.isPending) return;

    final serverText = _serverUrlController.text.trim();
    if (serverText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a server URL')),
      );
      return;
    }
    await AppConfig.setServerUrl(serverText);
    setState(() => _editingServer = false);

    if (!_formKey.currentState!.validate()) return;

    final username = _usernameController.text.trim();
    final displayName = _displayNameController.text.trim();
    final password = _passwordController.text;
    final inviteCode = _inviteCodeController.text.trim();
    registerMutation.run(ref, (tsx) async {
      final success = await tsx.get(authProvider.notifier).register(
        username,
        displayName,
        password,
        inviteCode: inviteCode.isEmpty ? null : inviteCode,
      );
      if (success && mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
      return success;
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final register = ref.watch(registerMutation);
    final submitting = register.isPending;

    return Scaffold(
      backgroundColor: context.pageBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF3F51FF)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Form(
            key: _formKey,
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              const Text(
                'Create Account',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF3F51FF),
                ),
              ),
              const SizedBox(height: 32),
              if (_editingServer) ...[
                _buildTextField(
                  controller: _serverUrlController,
                  hint: 'Server URL (e.g. point.example.com)',
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),
              ] else ...[
                GestureDetector(
                  onTap: () => setState(() => _editingServer = true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3F51FF).withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.dns_rounded,
                          size: 13,
                          color: Color(0xFF3F51FF),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          AppConfig.serverUrl.replaceAll(
                            RegExp(r'^https?://'),
                            '',
                          ),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF3F51FF),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'change',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF999999),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              _buildTextField(
                controller: _usernameController,
                hint: 'Username',
                textInputAction: TextInputAction.next,
                validator: (v) {
                  if (v == null || v.trim().length < 3) return 'Username must be at least 3 characters';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _displayNameController,
                hint: 'Display Name',
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _passwordController,
                hint: 'Password',
                obscure: true,
                textInputAction: TextInputAction.next,
                validator: (v) {
                  if (v == null || v.length < 8) return 'Password must be at least 8 characters';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _confirmPasswordController,
                hint: 'Confirm Password',
                obscure: true,
                textInputAction: TextInputAction.next,
                validator: (v) {
                  if (v != _passwordController.text) return 'Passwords do not match';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _inviteCodeController,
                hint: 'Invite Code',
                helperText: 'First user can skip',
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 20,
                child: switch (register) {
                  MutationError(:final error) => Text(
                      error.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                    ),
                  _ => auth.error != null
                      ? Text(
                          auth.error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.red, fontSize: 13),
                        )
                      : null,
                },
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3F51FF),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(
                      0xFF3F51FF,
                    ).withValues(alpha: 0.6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
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
                      : const Text(
                          'Create Account',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    bool obscure = false,
    String? helperText,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      validator: validator,
      controller: controller,
      obscureText: obscure,
      textInputAction: textInputAction,
      onFieldSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: hint,
        helperText: helperText,
        hintStyle: TextStyle(color: context.hintText),
        helperStyle: TextStyle(color: context.midGrey),
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
          borderSide: const BorderSide(color: Color(0xFF3F51FF), width: 1.5),
        ),
      ),
    );
  }
}
