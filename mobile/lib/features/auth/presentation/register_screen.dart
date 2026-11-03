import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/ui/ui.dart';
import '../application/auth_notifier.dart';
import 'auth_validators.dart';
import 'login_screen.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _displayName = TextEditingController();
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _showPassword = false;

  @override
  void dispose() {
    _displayName.dispose();
    _username.dispose();
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
    await ref.read(authNotifierProvider.notifier).register(
          email: _email.text,
          username: _username.text,
          password: _password.text,
          displayName: _displayName.text,
        );
    // Router redirects into the app on success.
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authNotifierProvider);

    return RxPage(
      title: 'Create Account',
      previousPageTitle: 'Sign In',
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.symmetric(vertical: RxSpace.l),
        child: AutofillGroup(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AuthBrand(
                  subtitle: 'Join drivers near you. It takes a minute.',
                ),
                const SizedBox(height: RxSpace.l),
                RxFormSection(
                  header: 'Profile',
                  children: [
                    RxFormField(
                      controller: _displayName,
                      placeholder: 'Your name',
                      textCapitalization: TextCapitalization.words,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.name],
                      validator: validateDisplayName,
                      maxLength: 60,
                    ),
                    RxFormField(
                      controller: _username,
                      placeholder: 'Username',
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.newUsername],
                      validator: validateUsername,
                      maxLength: 32,
                    ),
                  ],
                  footer: 'Friends find you by your username.',
                ),
                RxFormSection(
                  header: 'Account',
                  children: [
                    RxFormField(
                      controller: _email,
                      placeholder: 'Email',
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      validator: validateEmail,
                    ),
                    RxFormField(
                      controller: _password,
                      placeholder: 'Password (8+ characters)',
                      obscureText: !_showPassword,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.newPassword],
                      onFieldSubmitted: (_) => _submit(),
                      validator: validatePassword,
                      suffix: AuthRevealButton(
                        visible: _showPassword,
                        onTap: () =>
                            setState(() => _showPassword = !_showPassword),
                      ),
                    ),
                  ],
                ),
                if (auth.error != null) AuthInlineError(message: auth.error!),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      RxSpace.inset, RxSpace.m, RxSpace.inset, 0),
                  child: RxButton(
                    label: 'Create Account',
                    busy: auth.busy,
                    onPressed: _submit,
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
