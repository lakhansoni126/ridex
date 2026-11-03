import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/ui/ui.dart';
import '../domain/ride_engine.dart';
import '../domain/ride_state.dart';
import 'home_dashboard_screen.dart';

enum _FinishChoice { save, discard }

/// Full-screen live dashboard while recording a solo drive.
class RideDashboardScreen extends ConsumerStatefulWidget {
  const RideDashboardScreen({super.key});

  @override
  ConsumerState<RideDashboardScreen> createState() =>
      _RideDashboardScreenState();
}

class _RideDashboardScreenState extends ConsumerState<RideDashboardScreen> {
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(rideEngineProvider.notifier).startRide();
    });
  }

  Future<void> _finish() async {
    final state = ref.read(rideEngineProvider);
    final choice = await showRxActionSheet<_FinishChoice>(
      context,
      title: 'Finish this drive?',
      message:
          '${state.distance.toStringAsFixed(2)} km · ${formatDuration(state.durationSeconds)}',
      actions: const [
        RxSheetAction(
            label: 'Save Drive', value: _FinishChoice.save, isDefault: true),
        RxSheetAction(
            label: 'Discard Drive',
            value: _FinishChoice.discard,
            destructive: true),
      ],
    );
    if (choice == null || !mounted) return;
    final engine = ref.read(rideEngineProvider.notifier);
    setState(() => _finishing = true);
    if (choice == _FinishChoice.discard) {
      await engine.discardRide();
      if (mounted) context.pop();
      return;
    }
    final id = await engine.stopRide();
    ref.invalidate(driveStatsProvider);
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    if (id == null) {
      showRxToast(context, 'Drive was too short to save.', isError: true);
      context.pop();
    } else {
      showRxToast(context, 'Drive saved');
      context.pop();
      context.push('/drive/ride/$id');
    }
  }

  Future<void> _sendSos(RideState s) async {
    final lat = s.lastPosition?.latitude;
    final lon = s.lastPosition?.longitude;
    final where = lat == null
        ? ''
        : ' My location: https://maps.google.com/?q=$lat,$lon';
    final uri = Uri.parse(
        'sms:?body=${Uri.encodeComponent('SOS — I may need help on the road (RideX).$where')}');
    try {
      await launchUrl(uri);
    } catch (e) {
      if (mounted) showRxToast(context, 'Could not open Messages.', isError: true);
    }
    ref.read(rideEngineProvider.notifier).cancelSOS();
  }

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final s = ref.watch(rideEngineProvider);

    if (s.hasCrashed) {
      return _CrashOverlay(
        onOk: () => ref.read(rideEngineProvider.notifier).cancelSOS(),
        onSos: () => _sendSos(s),
      );
    }

    if (s.errorMessage != null) {
      return RxPage(
        title: 'Drive',
        leading: RxNavTextButton(
          label: 'Close',
          onPressed: () {
            ref.read(rideEngineProvider.notifier).clearError();
            context.pop();
          },
        ),
        child: Center(
          child: RxEmptyState(
            icon: CupertinoIcons.location_slash,
            title: 'Location Needed',
            message: s.errorMessage,
            actionLabel: 'Open Settings',
            onAction: () async {
              await Geolocator.openAppSettings();
            },
          ),
        ),
      );
    }

    final paused = s.isManuallyPaused || s.isPaused;
    final statusLabel = !s.isRecording
        ? 'Starting…'
        : s.isManuallyPaused
            ? 'Paused'
            : s.isPaused
                ? 'Auto-paused'
                : 'Recording';
    final statusColor = paused ? rx.warning : rx.destructive;
    final avg = s.durationSeconds > 0
        ? s.distance / (s.durationSeconds / 3600)
        : 0.0;

    return CupertinoPageScaffold(
      backgroundColor: rx.background,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: RxSpace.inset),
          child: Column(
            children: [
              const SizedBox(height: RxSpace.s),
              Row(
                children: [
                  RxMapButton(
                    icon: CupertinoIcons.chevron_down,
                    semanticLabel: 'Minimise dashboard',
                    onPressed: () => context.pop(),
                  ),
                  const Spacer(),
                  RxPill(
                    label: statusLabel.toUpperCase(),
                    color: statusColor,
                    icon: CupertinoIcons.circle_fill,
                  ),
                  const Spacer(),
                  RxMapButton(
                    icon: CupertinoIcons.map,
                    semanticLabel: 'Open live map',
                    onPressed: () => context.push('/map'),
                  ),
                ],
              ),
              if (s.weatherCondition != null) ...[
                const SizedBox(height: RxSpace.s),
                Text(
                  '${s.temperature?.toStringAsFixed(0) ?? '--'}°C · ${s.weatherCondition}',
                  style: rx.footnote,
                ),
              ],
              const Spacer(),
              Semantics(
                label: 'Speed ${s.currentSpeed.toStringAsFixed(0)} kilometres per hour',
                excludeSemantics: true,
                child: Column(
                  children: [
                    FittedBox(
                      child: Text(
                        s.currentSpeed.toStringAsFixed(0),
                        style: rx.numeric(132, weight: FontWeight.w700)
                            .copyWith(height: 1, letterSpacing: -4),
                      ),
                    ),
                    Text('km/h',
                        style: rx.title3.copyWith(color: rx.secondaryLabel)),
                  ],
                ),
              ),
              const Spacer(),
              RxCard(
                padding: const EdgeInsets.all(RxSpace.m + 4),
                radius: RxSpace.radiusLarge,
                child: RxMetricGrid(metrics: [
                  RxMetric(
                    label: 'Distance',
                    value: s.distance.toStringAsFixed(2),
                    unit: 'km',
                    icon: CupertinoIcons.map_fill,
                    iconColor: rx.info,
                  ),
                  RxMetric(
                    label: 'Time',
                    value: formatDuration(s.durationSeconds),
                    icon: CupertinoIcons.timer,
                    iconColor: rx.indigo,
                  ),
                  RxMetric(
                    label: 'Average',
                    value: avg.isFinite ? avg.toStringAsFixed(0) : '0',
                    unit: 'km/h',
                    icon: CupertinoIcons.gauge,
                    iconColor: rx.teal,
                  ),
                  RxMetric(
                    label: 'Top',
                    value: s.topSpeed.toStringAsFixed(0),
                    unit: 'km/h',
                    icon: CupertinoIcons.bolt_fill,
                    iconColor: rx.warning,
                  ),
                ]),
              ),
              const SizedBox(height: RxSpace.l),
              Row(
                children: [
                  Expanded(
                    child: RxButton.tinted(
                      label: s.isManuallyPaused ? 'Resume' : 'Pause',
                      icon: s.isManuallyPaused
                          ? CupertinoIcons.play_fill
                          : CupertinoIcons.pause_fill,
                      onPressed: s.isRecording
                          ? () => ref
                              .read(rideEngineProvider.notifier)
                              .togglePause()
                          : null,
                    ),
                  ),
                  const SizedBox(width: RxSpace.m),
                  Expanded(
                    child: RxButton(
                      label: 'Finish',
                      icon: CupertinoIcons.stop_fill,
                      busy: _finishing,
                      onPressed: s.isRecording ? _finish : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: RxSpace.m),
            ],
          ),
        ),
      ),
    );
  }
}

/// Possible crash: 30s countdown, then prompts to send an SOS text.
class _CrashOverlay extends StatefulWidget {
  const _CrashOverlay({required this.onOk, required this.onSos});

  final VoidCallback onOk;
  final VoidCallback onSos;

  @override
  State<_CrashOverlay> createState() => _CrashOverlayState();
}

class _CrashOverlayState extends State<_CrashOverlay> {
  static const _total = 30;
  int _left = _total;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    HapticFeedback.heavyImpact();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      setState(() => _left--);
      if (_left <= 0) {
        t.cancel();
        widget.onSos();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    const white = Color(0xFFFFFFFF);
    return CupertinoPageScaffold(
      backgroundColor: rx.destructive,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(RxSpace.l),
          child: Column(
            children: [
              const Spacer(),
              const Icon(CupertinoIcons.exclamationmark_triangle_fill,
                  size: 72, color: white),
              const SizedBox(height: RxSpace.m),
              Text('Possible Crash Detected',
                  style: rx.title1.copyWith(color: white),
                  textAlign: TextAlign.center),
              const SizedBox(height: RxSpace.s),
              Text(
                'If you don\'t respond, RideX will open an SOS message with your location in $_left s.',
                style: rx.body.copyWith(color: white.withOpacity(0.9)),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  color: white,
                  borderRadius: BorderRadius.circular(RxSpace.radius),
                  onPressed: () {
                    _timer?.cancel();
                    widget.onOk();
                  },
                  child: Text("I'm OK",
                      style: rx.headline.copyWith(color: rx.destructive)),
                ),
              ),
              const SizedBox(height: RxSpace.m),
              CupertinoButton(
                onPressed: () {
                  _timer?.cancel();
                  widget.onSos();
                },
                child: Text('Send SOS Now',
                    style: rx.headline.copyWith(color: white)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
