import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/glass.dart';
import '../application/auth_notifier.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _email = TextEditingController();
  final _username = TextEditingController();
  final _displayName = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _email.dispose();
    _username.dispose();
    _displayName.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final ok = await ref.read(authNotifierProvider.notifier).register(
          email: _email.text.trim(),
          username: _username.text.trim(),
          password: _password.text,
          displayName: _displayName.text.trim(),
        );
    if (ok && mounted) context.go('/permissions');
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authNotifierProvider);
    final theme = Theme.of(context);

    return GlassScaffold(
      appBar: const GlassAppBar(title: 'Join RideX'),
      padding: const EdgeInsets.all(24),
      body: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Create your profile and hit the road with the community.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              GlassFormPanel(
                children: [
                  GlassFormField(
                    controller: _displayName,
                    label: 'Display name',
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Required' : null,
                  ),
                  GlassFormField(
                    controller: _username,
                    label: 'Username',
                    validator: (v) {
                      if (v == null || v.length < 3) return 'Min 3 chars';
                      if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(v)) {
                        return 'Letters, numbers, underscore';
                      }
                      return null;
                    },
                  ),
                  GlassFormField(
                    controller: _email,
                    label: 'Email',
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) =>
                        (v == null || !v.contains('@')) ? 'Enter email' : null,
                  ),
                  GlassFormField(
                    controller: _password,
                    label: 'Password',
                    obscureText: true,
                    validator: (v) =>
                        (v == null || v.length < 8) ? 'Min 8 characters' : null,
                  ),
                ],
              ),
              if (auth.error != null) ...[
                const SizedBox(height: 16),
                Text(auth.error!, style: const TextStyle(color: AppTheme.accent)),
              ],
              const SizedBox(height: 32),
              GlassButton(
                label: 'CREATE ACCOUNT',
                busy: auth.busy,
                onPressed: auth.busy ? null : _submit,
              ),
              TextButton(
                onPressed: () => context.go('/login'),
                child: Text(
                  'Already have an account? Sign in',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
