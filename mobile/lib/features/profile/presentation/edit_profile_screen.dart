import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/ui/ui.dart';
import '../../auth/application/auth_notifier.dart';
import '../../auth/presentation/auth_validators.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _bio;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authNotifierProvider).user;
    _name = TextEditingController(text: user?.displayName ?? '');
    _bio = TextEditingController(text: user?.bio ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      await ref.read(authNotifierProvider.notifier).updateProfile(
            displayName: _name.text.trim(),
            bio: _bio.text.trim(),
          );
      if (!mounted) return;
      showRxToast(context, 'Profile saved');
      context.pop();
    } catch (e) {
      if (mounted) showRxError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authNotifierProvider).user;
    return RxPage(
      title: 'Edit Profile',
      previousPageTitle: 'Profile',
      trailing: RxNavTextButton(
        label: 'Save',
        bold: true,
        busy: _busy,
        onPressed: _save,
      ),
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: RxSpace.l),
          children: [
            RxFormSection(
              header: 'Name',
              children: [
                RxFormField(
                  controller: _name,
                  placeholder: 'Display name',
                  textCapitalization: TextCapitalization.words,
                  validator: validateDisplayName,
                  maxLength: 60,
                ),
              ],
            ),
            RxFormSection(
              header: 'Bio',
              footer: 'Up to 280 characters. Shown to friends.',
              children: [
                RxFormField(
                  controller: _bio,
                  placeholder: 'Daily driver, weekend canyon runs…',
                  maxLines: 4,
                  maxLength: 280,
                  textCapitalization: TextCapitalization.sentences,
                ),
              ],
            ),
            RxSection(
              header: 'Account',
              footer: 'Username and email can\'t be changed yet.',
              children: [
                RxTile(
                  title: 'Username',
                  detail: '@${user?.username ?? ''}',
                  chevron: false,
                ),
                RxTile(
                  title: 'Email',
                  detail: user?.email ?? '',
                  chevron: false,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
