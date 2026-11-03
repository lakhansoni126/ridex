import 'package:flutter/cupertino.dart';

import '../../core/errors.dart';
import '../../core/theme/app_theme.dart';
import 'rx_button.dart';

/// Centered illustration + copy + optional action, for empty lists.
class RxEmptyState extends StatelessWidget {
  const RxEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: RxSpace.xl, vertical: RxSpace.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: rx.tertiaryLabel),
          const SizedBox(height: RxSpace.m),
          Text(title, style: rx.title3, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: RxSpace.s),
            Text(message!,
                style: rx.subheadline, textAlign: TextAlign.center),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: RxSpace.l),
            RxButton.tinted(
              label: actionLabel!,
              onPressed: onAction,
              expand: false,
            ),
          ],
        ],
      ),
    );
  }
}

/// Friendly error with a retry button.
class RxErrorState extends StatelessWidget {
  const RxErrorState({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final offline = isOfflineError(error);
    return RxEmptyState(
      icon: offline
          ? CupertinoIcons.wifi_slash
          : CupertinoIcons.exclamationmark_triangle,
      title: offline ? "You're offline" : "Couldn't load",
      message: friendlyError(error),
      actionLabel: onRetry == null ? null : 'Try Again',
      onAction: onRetry,
    );
  }
}

/// Sliver that fills remaining space and centers [child].
class RxSliverCenter extends StatelessWidget {
  const RxSliverCenter({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(child: child),
    );
  }
}

class RxSliverLoading extends StatelessWidget {
  const RxSliverLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const RxSliverCenter(child: CupertinoActivityIndicator(radius: 14));
  }
}
