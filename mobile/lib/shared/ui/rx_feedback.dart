import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../core/errors.dart';
import '../../core/theme/app_theme.dart';

/// iOS-style transient banner that slides from the top (replaces SnackBars).
void showRxToast(
  BuildContext context,
  String message, {
  bool isError = false,
  IconData? icon,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  if (isError) {
    HapticFeedback.heavyImpact();
  } else {
    HapticFeedback.selectionClick();
  }
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => _Toast(
      message: message,
      isError: isError,
      icon: icon,
      onDone: () => entry.remove(),
    ),
  );
  overlay.insert(entry);
}

/// Shows [error] as a friendly toast.
void showRxError(BuildContext context, Object error) =>
    showRxToast(context, friendlyError(error), isError: true);

class _Toast extends StatefulWidget {
  const _Toast({
    required this.message,
    required this.isError,
    required this.onDone,
    this.icon,
  });

  final String message;
  final bool isError;
  final IconData? icon;
  final VoidCallback onDone;

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    reverseDuration: const Duration(milliseconds: 200),
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _c.forward();
    _timer = Timer(const Duration(milliseconds: 2800), _dismiss);
  }

  Future<void> _dismiss() async {
    _timer?.cancel();
    if (!mounted) return;
    await _c.reverse();
    widget.onDone();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final top = MediaQuery.paddingOf(context).top + 8;
    final color = widget.isError ? rx.destructive : rx.success;
    final icon = widget.icon ??
        (widget.isError
            ? CupertinoIcons.exclamationmark_circle_fill
            : CupertinoIcons.checkmark_circle_fill);
    final curved = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return Positioned(
      top: top,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, -1.4), end: Offset.zero)
            .animate(curved),
        child: FadeTransition(
          opacity: curved,
          child: GestureDetector(
            onTap: _dismiss,
            onVerticalDragEnd: (_) => _dismiss(),
            child: Semantics(
              liveRegion: true,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: rx.cardElevated,
                  borderRadius: BorderRadius.circular(RxSpace.radiusLarge),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 24,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(icon, color: color, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.message,
                        style: rx.subheadline.copyWith(color: rx.label),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Destructive confirmation alert. Returns true when confirmed.
Future<bool> confirmRx(
  BuildContext context, {
  required String title,
  String? message,
  required String confirmLabel,
  bool destructive = true,
  String cancelLabel = 'Cancel',
}) async {
  final result = await showCupertinoDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => CupertinoAlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        CupertinoDialogAction(
          isDefaultAction: !destructive,
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(cancelLabel),
        ),
        CupertinoDialogAction(
          isDestructiveAction: destructive,
          isDefaultAction: destructive,
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

class RxSheetAction<T> {
  const RxSheetAction({
    required this.label,
    required this.value,
    this.destructive = false,
    this.isDefault = false,
  });

  final String label;
  final T value;
  final bool destructive;
  final bool isDefault;
}

/// Bottom action sheet. Returns the chosen value, or null on cancel.
Future<T?> showRxActionSheet<T>(
  BuildContext context, {
  String? title,
  String? message,
  required List<RxSheetAction<T>> actions,
}) {
  return showCupertinoModalPopup<T>(
    context: context,
    builder: (ctx) => CupertinoActionSheet(
      title: title == null ? null : Text(title),
      message: message == null ? null : Text(message),
      actions: [
        for (final a in actions)
          CupertinoActionSheetAction(
            isDestructiveAction: a.destructive,
            isDefaultAction: a.isDefault,
            onPressed: () => Navigator.of(ctx).pop(a.value),
            child: Text(a.label),
          ),
      ],
      cancelButton: CupertinoActionSheetAction(
        onPressed: () => Navigator.of(ctx).pop(),
        child: const Text('Cancel'),
      ),
    ),
  );
}
