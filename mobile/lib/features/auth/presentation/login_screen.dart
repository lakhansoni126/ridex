import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/ui/ui.dart';
import '../application/auth_notifier.dart';
import 'auth_validators.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _showPassword = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      HapticFeedback.heavyImpact();
      return;
    }
    TextInput.finishAutofillContext();
    await ref
        .read(authNotifierProvider.notifier)
        .login(_email.text, _password.text);
    // Router redirects to /drive on success.
  }

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final auth = ref.watch(authNotifierProvider);

    return CupertinoPageScaffold(
      backgroundColor: rx.background,
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.symmetric(vertical: RxSpace.l),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: AutofillGroup(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _Brand(
                          subtitle:
                              'Sign in to join group drives and the car community.',
                        ),
                        const SizedBox(height: RxSpace.xl),
                        RxFormSection(
                          children: [
                            RxFormField(
                              controller: _email,
                              placeholder: 'Email',
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.email],
                              autocorrect: false,
                              validator: validateEmail,
                            ),
                            RxFormField(
                              controller: _password,
                              placeholder: 'Password',
                              obscureText: !_showPassword,
                              textInputAction: TextInputAction.go,
                              autofillHints: const [AutofillHints.password],
                              onFieldSubmitted: (_) => _submit(),
                              validator: (v) => (v == null || v.isEmpty)
                                  ? 'Enter your password'
                                  : null,
                              suffix: _RevealButton(
                                visible: _showPassword,
                                onTap: () => setState(
                                    () => _showPassword = !_showPassword),
                              ),
                            ),
                          ],
                        ),
                        if (auth.error != null)
                          _InlineError(message: auth.error!),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                              RxSpace.inset, RxSpace.m, RxSpace.inset, 0),
                          child: RxButton(
                            label: 'Sign In',
                            busy: auth.busy,
                            onPressed: _submit,
                          ),
                        ),
                        const SizedBox(height: RxSpace.s),
                        Center(
                          child: RxButton.plain(
                            label: 'Create an Account',
                            onPressed: () {
                              ref
                                  .read(authNotifierProvider.notifier)
                                  .clearError();
                              context.push('/register');
                            },
                          ),
                        ),
                        const SizedBox(height: RxSpace.l),
                        Center(child: Text('RideX v1.2', style: rx.caption2)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({super.key, required this.subtitle});

  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: RxSpace.inset + 8),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.asset(
              'assets/branding/exports/ridex-icon-1024.png',
              width: 84,
              height: 84,
              errorBuilder: (_, __, ___) => RxIconBadge(
                icon: CupertinoIcons.car_detailed,
                color: rx.accent,
                size: 84,
              ),
            ),
          ),
          const SizedBox(height: RxSpace.m),
          Text('RideX', style: rx.largeTitle),
          const SizedBox(height: RxSpace.s),
          Text(subtitle, style: rx.subheadline, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _RevealButton extends StatelessWidget {
  const _RevealButton({super.key, required this.visible, required this.onTap});

  final bool visible;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return RxNavIconButton(
      icon: visible ? CupertinoIcons.eye_slash : CupertinoIcons.eye,
      semanticLabel: visible ? 'Hide password' : 'Show password',
      onPressed: onTap,
    );
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            RxSpace.inset + 4, RxSpace.xs, RxSpace.inset, 0),
        child: Row(
          children: [
            Icon(CupertinoIcons.exclamationmark_circle_fill,
                size: 16, color: rx.destructive),
            const SizedBox(width: 6),
            Expanded(
              child: Text(message,
                  style: rx.footnote.copyWith(color: rx.destructive)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Re-exported so the register screen shares the same look.
class AuthInlineError extends _InlineError {
  const AuthInlineError({super.key, required super.message});
}

class AuthBrand extends _Brand {
  const AuthBrand({super.key, required super.subtitle});
}

class AuthRevealButton extends _RevealButton {
  const AuthRevealButton({super.key, required super.visible, required super.onTap});
}
