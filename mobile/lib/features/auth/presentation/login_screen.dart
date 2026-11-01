import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/glass_container.dart';
import '../application/auth_notifier.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await ref
        .read(authNotifierProvider.notifier)
        .login(_email.text.trim(), _password.text);
    if (ok && mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authNotifierProvider);
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 32),
                Text(
                  'RideX',
                  style: theme.textTheme.displayMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Sign in to join group drives and the car community.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 40),
                GlassContainer(
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          labelStyle: TextStyle(color: AppTheme.textSecondary),
                          border: InputBorder.none,
                        ),
                        validator: (v) =>
                            (v == null || !v.contains('@')) ? 'Enter email' : null,
                      ),
                      const Divider(color: Colors.white12),
                      TextFormField(
                        controller: _password,
                        obscureText: true,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Password',
                          labelStyle: TextStyle(color: AppTheme.textSecondary),
                          border: InputBorder.none,
                        ),
                        validator: (v) =>
                            (v == null || v.length < 8) ? 'Min 8 characters' : null,
                      ),
                    ],
                  ),
                ),
                if (auth.error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    auth.error!,
                    style: const TextStyle(color: AppTheme.accent),
                  ),
                ],
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: auth.busy ? null : _submit,
                    child: auth.busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('SIGN IN'),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: TextButton(
                    onPressed: () => context.push('/register'),
                    child: const Text(
                      'Create an account',
                      style: TextStyle(color: Colors.white70),
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
}
