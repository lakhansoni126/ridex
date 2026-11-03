import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';

enum RxButtonKind {
  /// Prominent: one primary action per screen.
  filled,

  /// Tinted background, accent label: secondary actions.
  tinted,

  /// Text only: tertiary actions and links.
  plain,

  /// Filled red: destructive confirmations.
  destructive,
}

/// Full-width 50pt iOS button with haptics and a busy state.
class RxButton extends StatelessWidget {
  const RxButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = RxButtonKind.filled,
    this.icon,
    this.busy = false,
    this.expand = true,
  });

  const RxButton.tinted({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.expand = true,
  }) : kind = RxButtonKind.tinted;

  const RxButton.plain({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.expand = false,
  }) : kind = RxButtonKind.plain;

  final String label;
  final VoidCallback? onPressed;
  final RxButtonKind kind;
  final IconData? icon;
  final bool busy;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final enabled = onPressed != null && !busy;

    final (Color bg, Color fg) = switch (kind) {
      RxButtonKind.filled => (rx.accent, rx.onAccent),
      RxButtonKind.tinted => (rx.accentTint, rx.accent),
      RxButtonKind.plain => (const Color(0x00000000), rx.accent),
      RxButtonKind.destructive => (rx.destructive, rx.onAccent),
    };

    final content = busy
        ? CupertinoActivityIndicator(
            color: kind == RxButtonKind.filled ||
                    kind == RxButtonKind.destructive
                ? rx.onAccent
                : null,
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: fg),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label,
                  style: rx.headline.copyWith(color: fg),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );

    final button = CupertinoButton(
      padding: EdgeInsets.symmetric(
        horizontal: kind == RxButtonKind.plain ? 8 : 20,
      ),
      minSize: kind == RxButtonKind.plain ? RxSpace.minTouch : 50,
      color: kind == RxButtonKind.plain ? null : bg,
      disabledColor: kind == RxButtonKind.plain ? const Color(0x00000000) : rx.fill,
      borderRadius: BorderRadius.circular(RxSpace.radius),
      onPressed: enabled
          ? () {
              HapticFeedback.lightImpact();
              onPressed!();
            }
          : null,
      child: busy
          ? content
          : Opacity(opacity: enabled ? 1 : 0.5, child: content),
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: expand ? SizedBox(width: double.infinity, child: button) : button,
    );
  }
}
