import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors.dart';
import '../../../core/providers.dart';
import '../../../data/api/api_client.dart';
import '../../../shared/ui/ui.dart';
import 'rides_screen.dart';

class JoinRideScreen extends ConsumerStatefulWidget {
  const JoinRideScreen({super.key, this.initialCode});

  final String? initialCode;

  @override
  ConsumerState<JoinRideScreen> createState() => _JoinRideScreenState();
}

class _JoinRideScreenState extends ConsumerState<JoinRideScreen> {
  static const _codeLength = 6;
  late final TextEditingController _code;
  final _focus = FocusNode();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _code = TextEditingController(text: _sanitize(widget.initialCode ?? ''));
    _code.addListener(() => setState(() => _error = null));
  }

  @override
  void dispose() {
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  static String _sanitize(String raw) {
    final cleaned = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    return cleaned.length > _codeLength
        ? cleaned.substring(0, _codeLength)
        : cleaned;
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = _sanitize(data?.text ?? '');
    if (text.isEmpty) {
      if (mounted) showRxToast(context, 'Nothing to paste.', isError: true);
      return;
    }
    _code.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  String _message(Object e) {
    if (e is ApiException) {
      switch (e.statusCode) {
        case 404:
          return 'No drive found with that code. Check it and try again.';
        case 409:
          return 'That drive has already ended.';
        case 403:
          return 'The host removed you from this drive.';
      }
    }
    return friendlyError(e);
  }

  Future<void> _join() async {
    if (_code.text.length != _codeLength || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ride = await ref
          .read(ridesRepositoryProvider)
          .joinRide(joinCode: _code.text);
      ref.invalidate(discoverRidesProvider);
      ref.invalidate(myRidesProvider);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      showRxToast(context, 'You joined "${ride.title}"');
      context.pushReplacement('/rides/live/${ride.id}');
    } catch (e) {
      if (mounted) {
        HapticFeedback.heavyImpact();
        setState(() => _error = _message(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final ready = _code.text.length == _codeLength;
    return RxPage(
      title: 'Join a Drive',
      leading: RxNavTextButton(
        label: 'Cancel',
        onPressed: () => context.pop(),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            RxSpace.inset, RxSpace.xl, RxSpace.inset, RxSpace.xl),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          Center(
            child: RxIconBadge(
              icon: CupertinoIcons.qrcode,
              color: rx.accent,
              size: 64,
            ),
          ),
          const SizedBox(height: RxSpace.m),
          Text('Enter the drive code',
              style: rx.title2, textAlign: TextAlign.center),
          const SizedBox(height: RxSpace.s),
          Text(
            'Ask the host for the 6-character code shown on their drive.',
            style: rx.subheadline,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: RxSpace.l),
          Semantics(
            label: 'Drive code',
            textField: true,
            child: CupertinoTextField(
              controller: _code,
              focusNode: _focus,
              autofocus: widget.initialCode == null,
              textAlign: TextAlign.center,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.visiblePassword,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _join(),
              inputFormatters: [
                TextInputFormatter.withFunction((oldValue, newValue) {
                  final text = _sanitize(newValue.text);
                  return TextEditingValue(
                    text: text,
                    selection: TextSelection.collapsed(offset: text.length),
                  );
                }),
              ],
              placeholder: 'ABC123',
              placeholderStyle: rx.numeric(32).copyWith(
                    color: rx.tertiaryLabel,
                    letterSpacing: 8,
                  ),
              style: rx.numeric(32).copyWith(letterSpacing: 8),
              cursorColor: rx.accent,
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: BoxDecoration(
                color: rx.card,
                borderRadius: BorderRadius.circular(RxSpace.radiusLarge),
                border: Border.all(
                  color: _error != null ? rx.destructive : rx.card,
                  width: 1.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: RxSpace.s),
          Row(
            children: [
              Expanded(
                child: _error == null
                    ? Text('${_code.text.length}/$_codeLength',
                        style: rx.footnote)
                    : Text(_error!,
                        style: rx.footnote.copyWith(color: rx.destructive)),
              ),
              RxButton.plain(
                label: 'Paste',
                icon: CupertinoIcons.doc_on_clipboard,
                onPressed: _paste,
              ),
            ],
          ),
          const SizedBox(height: RxSpace.l),
          RxButton(
            label: 'Join Drive',
            busy: _busy,
            onPressed: ready ? _join : null,
          ),
        ],
      ),
    );
  }
}
