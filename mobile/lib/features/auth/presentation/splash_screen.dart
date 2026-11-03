import 'package:flutter/cupertino.dart';

import '../../../shared/ui/ui.dart';

/// Shown for the instant it takes to read the cached session.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    return CupertinoPageScaffold(
      backgroundColor: rx.background,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Image.asset(
                'assets/branding/exports/ridex-icon-1024.png',
                width: 96,
                height: 96,
                errorBuilder: (_, __, ___) => const SizedBox(
                  width: 96,
                  height: 96,
                ),
              ),
            ),
            const SizedBox(height: RxSpace.l),
            const CupertinoActivityIndicator(),
          ],
        ),
      ),
    );
  }
}
