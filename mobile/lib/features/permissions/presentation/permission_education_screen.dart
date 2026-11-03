import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/ui/ui.dart';

/// Current location permission, re-read whenever invalidated.
final locationPermissionProvider =
    FutureProvider.autoDispose<LocationPermission>((ref) async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    return LocationPermission.denied;
  }
  return Geolocator.checkPermission();
});

bool permissionGranted(LocationPermission? p) =>
    p == LocationPermission.always || p == LocationPermission.whileInUse;

/// Explains why RideX needs location before showing the system prompt.
class PermissionEducationScreen extends ConsumerStatefulWidget {
  const PermissionEducationScreen({super.key});

  @override
  ConsumerState<PermissionEducationScreen> createState() =>
      _PermissionEducationScreenState();
}

class _PermissionEducationScreenState
    extends ConsumerState<PermissionEducationScreen> {
  bool _busy = false;

  Future<void> _request() async {
    setState(() => _busy = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (!mounted) return;
        showRxToast(context, 'Turn on Location in your phone settings.',
            isError: true);
        await Geolocator.openLocationSettings();
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        final open = await confirmRx(
          context,
          title: 'Location Is Off for RideX',
          message:
              'Open Settings and allow location access to record drives and share your position.',
          confirmLabel: 'Open Settings',
          destructive: false,
        );
        if (open) await Geolocator.openAppSettings();
        return;
      }
      ref.invalidate(locationPermissionProvider);
      if (!mounted) return;
      if (permissionGranted(permission)) {
        showRxToast(context, 'Location enabled');
        context.pop();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    return RxPage(
      title: '',
      leading: RxNavTextButton(
        label: 'Not Now',
        onPressed: () => context.pop(),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            RxSpace.inset, RxSpace.l, RxSpace.inset, RxSpace.l),
        children: [
          Center(
            child: RxIconBadge(
              icon: CupertinoIcons.location_fill,
              color: rx.info,
              size: 88,
            ),
          ),
          const SizedBox(height: RxSpace.l),
          Text('Allow Location Access',
              style: rx.title1, textAlign: TextAlign.center),
          const SizedBox(height: RxSpace.s),
          Text(
            'RideX uses your location only while you choose to:',
            style: rx.subheadline,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: RxSpace.l),
          _Reason(
            icon: CupertinoIcons.speedometer,
            color: rx.accent,
            title: 'Record your drives',
            body: 'Speed, distance and a map of your route — stored on your phone.',
          ),
          _Reason(
            icon: CupertinoIcons.person_3_fill,
            color: rx.success,
            title: 'Drive together',
            body: 'Your group sees where you are during a live group drive.',
          ),
          _Reason(
            icon: CupertinoIcons.location_circle_fill,
            color: rx.info,
            title: 'Share with friends',
            body: 'Only the friends you pick, for as long as you choose.',
          ),
          const SizedBox(height: RxSpace.m),
          Text(
            'While sharing, Android shows a notification so you always know RideX is using your location. Stop anytime.',
            style: rx.footnote,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: RxSpace.l),
          RxButton(
            label: 'Continue',
            busy: _busy,
            onPressed: _request,
          ),
        ],
      ),
    );
  }
}

class _Reason extends StatelessWidget {
  const _Reason({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    return Padding(
      padding: const EdgeInsets.only(bottom: RxSpace.m),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 30),
          const SizedBox(width: RxSpace.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: rx.headline),
                const SizedBox(height: 2),
                Text(body, style: rx.subheadline),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
