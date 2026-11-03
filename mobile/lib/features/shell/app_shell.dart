import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../data/ws/ws_client.dart';
import '../../services/background_location_service.dart';
import '../../shared/ui/ui.dart';
import '../friends/presentation/friends_screen.dart';

/// Root of the signed-in app: five tabs with an iOS tab bar.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Resume live tracking that was active before the app was killed.
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreTracking());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Push anything buffered while backgrounded/offline.
      unawaited(ref.read(backgroundLocationServiceProvider).flush());
      ref.invalidate(friendRequestsProvider);
    }
  }

  Future<void> _restoreTracking() async {
    final bg = ref.read(backgroundLocationServiceProvider);
    final tokens = ref.read(tokenStoreProvider);
    try {
      final shares = await ref.read(sharesRepositoryProvider).listShares();
      final active = shares.activeMine;
      if (active != null && bg.activeShareId == null) {
        final ws = LocationShareWsSession(tokenProvider: tokens.readAccessToken);
        await ws.connect(onMessage: (_) {});
        final ok = await bg.startForShare(shareId: active.id, ws: ws);
        if (!ok) await ws.disconnect();
      }
    } catch (_) {}
    try {
      final mine =
          await ref.read(ridesRepositoryProvider).listRides(scope: 'mine');
      for (final ride in mine) {
        if (ride.isLive && bg.activeRideId == null) {
          await bg.startForRide(rideId: ride.id);
          break;
        }
      }
    } catch (_) {}
    unawaited(bg.flush());
  }

  void _onTap(int index) {
    HapticFeedback.selectionClick();
    widget.shell.goBranch(
      index,
      // Tapping the active tab pops to its root, like iOS.
      initialLocation: index == widget.shell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final requests = ref.watch(friendRequestsProvider).valueOrNull;
    final pending = requests?.incoming.length ?? 0;
    final tracking = ref.watch(backgroundLocationServiceProvider);

    return CupertinoPageScaffold(
      backgroundColor: rx.background,
      child: Column(
        children: [
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeBottom: true,
              child: widget.shell,
            ),
          ),
          ValueListenableBuilder<TrackingStatus>(
            valueListenable: tracking.status,
            builder: (context, status, _) => _LiveBanner(status: status),
          ),
          CupertinoTabBar(
            currentIndex: widget.shell.currentIndex,
            onTap: _onTap,
            activeColor: rx.accent,
            inactiveColor: rx.gray,
            backgroundColor: rx.bar,
            iconSize: 26,
            border: Border(top: BorderSide(color: rx.separator, width: 0.0)),
            items: [
              const BottomNavigationBarItem(
                icon: Icon(CupertinoIcons.speedometer),
                label: 'Drive',
              ),
              const BottomNavigationBarItem(
                icon: Icon(CupertinoIcons.flag),
                activeIcon: Icon(CupertinoIcons.flag_fill),
                label: 'Drives',
              ),
              const BottomNavigationBarItem(
                icon: Icon(CupertinoIcons.photo_on_rectangle),
                label: 'Feed',
              ),
              BottomNavigationBarItem(
                icon: _Badge(
                  count: pending,
                  child: const Icon(CupertinoIcons.person_2),
                ),
                activeIcon: _Badge(
                  count: pending,
                  child: const Icon(CupertinoIcons.person_2_fill),
                ),
                label: 'Friends',
              ),
              const BottomNavigationBarItem(
                icon: Icon(CupertinoIcons.person_crop_circle),
                activeIcon: Icon(CupertinoIcons.person_crop_circle_fill),
                label: 'Profile',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Thin banner above the tab bar while location is being shared.
class _LiveBanner extends StatelessWidget {
  const _LiveBanner({required this.status});

  final TrackingStatus status;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    if (!status.isTracking) return const SizedBox.shrink();
    final label = status.rideId != null && status.shareId != null
        ? 'Live in a group drive · Sharing location'
        : status.rideId != null
            ? 'Live in a group drive'
            : 'Sharing your location';
    return RxPressable(
      onTap: () => status.rideId != null
          ? context.push('/rides/live/${status.rideId}')
          : context.push('/friends/sharing'),
      child: Container(
        width: double.infinity,
        color: rx.accent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const Icon(CupertinoIcons.location_fill,
                size: 14, color: Color(0xFFFFFFFF)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: rx.footnote.copyWith(
                  color: const Color(0xFFFFFFFF),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Icon(CupertinoIcons.chevron_right,
                size: 14, color: Color(0xFFFFFFFF)),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.count, required this.child});

  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return child;
    final rx = context.rx;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          right: -8,
          top: -4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            constraints: const BoxConstraints(minWidth: 18),
            decoration: BoxDecoration(
              color: rx.destructive,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              count > 9 ? '9+' : '$count',
              textAlign: TextAlign.center,
              style: rx.caption2.copyWith(
                color: const Color(0xFFFFFFFF),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
