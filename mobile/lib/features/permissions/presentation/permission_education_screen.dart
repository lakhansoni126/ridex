import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/glass.dart';

/// Explains why RideX needs Always location before requesting it.
class PermissionEducationScreen extends ConsumerStatefulWidget {
  const PermissionEducationScreen({super.key});

  @override
  ConsumerState<PermissionEducationScreen> createState() =>
      _PermissionEducationScreenState();
}

class _PermissionEducationScreenState
    extends ConsumerState<PermissionEducationScreen> {
  bool _busy = false;
  String? _message;

  Future<void> _request() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        setState(() => _message = 'Turn on location services to continue.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() =>
            _message = 'Location is required for group drives and sharing.');
        return;
      }
      if (permission == LocationPermission.whileInUse) {
        await Geolocator.requestPermission();
      }
      if (mounted) context.go('/');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassScaffold(
      padding: const EdgeInsets.all(24),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          Text('Stay connected on the road', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          Text(
            'RideX uses your location in the background so friends can see you '
            'during live group drives and while you choose to share.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 32),
          GlassContainer(
            variant: GlassVariant.intense,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _row(Icons.groups_outlined, 'Live group drives',
                    'Show your position to participants while a drive is live.'),
                const SizedBox(height: 20),
                _row(Icons.share_location, 'Optional location sharing',
                    'Share with chosen friends for a set duration — you can stop anytime.'),
                const SizedBox(height: 20),
                _row(Icons.lock_outline, 'You stay in control',
                    'We only stream when a drive is live or you start a share.'),
              ],
            ),
          ),
          if (_message != null) ...[
            const SizedBox(height: 16),
            Text(_message!, style: const TextStyle(color: AppTheme.accent)),
          ],
          const Spacer(),
          GlassButton(
            label: 'ALLOW LOCATION',
            busy: _busy,
            onPressed: _busy ? null : _request,
          ),
          const SizedBox(height: 12),
          GlassButton(
            label: 'Skip for now',
            style: GlassButtonStyle.secondary,
            onPressed: () => context.go('/'),
          ),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String title, String body) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppTheme.accent, size: 28),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: AppTheme.textPrimary, fontSize: 16)),
              const SizedBox(height: 4),
              Text(body,
                  style: const TextStyle(color: AppTheme.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }
}
