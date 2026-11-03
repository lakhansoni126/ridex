import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/providers.dart';
import '../../../data/api/friends_repository.dart';
import '../../../data/api/rides_repository.dart';
import '../../../data/ws/ws_client.dart';
import '../../../services/background_location_service.dart';
import '../../../shared/ui/ui.dart';
import '../../auth/application/auth_notifier.dart';
import 'rides_screen.dart';

class LiveRideMapScreen extends ConsumerStatefulWidget {
  const LiveRideMapScreen({super.key, required this.rideId});

  final String rideId;

  @override
  ConsumerState<LiveRideMapScreen> createState() => _LiveRideMapScreenState();
}

class _LiveRideMapScreenState extends ConsumerState<LiveRideMapScreen> {
  final MapController _map = MapController();
  final Map<String, ParticipantDto> _participants = {};
  RideDto? _ride;
  RideWsSession? _ws;
  Object? _loadError;
  bool _loading = true;
  bool _mapReady = false;
  bool _fittedOnce = false;
  bool _followMe = false;
  bool _permissionWarning = false;
  bool _actionBusy = false;
  String _myStatus = 'joined';
  Timer? _staleTicker;

  late final BackgroundLocationService _bg =
      ref.read(backgroundLocationServiceProvider);

  String? get _meId => ref.read(authNotifierProvider).user?.id;
  bool get _isHost => _ride != null && _ride!.hostId == _meId;
  bool get _isParticipant =>
      _ride != null &&
      (_ride!.isParticipant || _participants.containsKey(_meId));

  @override
  void initState() {
    super.initState();
    _bootstrap();
    // Re-render periodically so "stale" markers and "last seen" stay honest.
    _staleTicker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _staleTicker?.cancel();
    _bg.attachRideWs(null);
    _ws?.disconnect();
    _map.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final ride = await ref.read(ridesRepositoryProvider).getRide(widget.rideId);
      if (!mounted) return;
      _participants
        ..clear()
        ..addEntries(ride.participants.map((p) => MapEntry(p.userId, p)));
      final me = _participants[_meId];
      setState(() {
        _ride = ride;
        _myStatus = me?.status ?? 'joined';
        _loading = false;
      });
      _fitIfReady();

      if (!_isParticipant || ride.isOver) return;

      final ws = RideWsSession(
        rideId: ride.id,
        tokenProvider: ref.read(tokenStoreProvider).readAccessToken,
      );
      _ws = ws;
      ws.state.addListener(_onWsState);
      await ws.connect(onMessage: _onWsMessage);
      if (!mounted) return;
      _bg.attachRideWs(ws);
      if (ride.isLive) await _startTracking();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = e;
          _loading = false;
        });
      }
    }
  }

  void _onWsState() {
    if (mounted) setState(() {});
  }

  Future<void> _startTracking() async {
    final status = _myStatus == 'joined' ? 'riding' : _myStatus;
    final ok = await _bg.startForRide(
      rideId: widget.rideId,
      status: status,
      ws: _ws,
    );
    if (!mounted) return;
    setState(() {
      _permissionWarning = !ok;
      if (ok && _myStatus == 'joined') _myStatus = 'riding';
    });
  }

  void _onWsMessage(Map<String, dynamic> msg) {
    if (!mounted) return;
    final type = msg['type'] as String?;
    final userId = msg['user_id'] as String?;
    switch (type) {
      case 'participant_update':
        if (userId == null) return;
        final existing = _participants[userId] ??
            ParticipantDto(
              id: userId,
              rideId: widget.rideId,
              userId: userId,
              role: 'participant',
              status: 'joined',
            );
        setState(() {
          _participants[userId] = existing.copyWith(
            status: msg['status'] as String?,
            lat: (msg['lat'] as num?)?.toDouble(),
            lon: (msg['lon'] as num?)?.toDouble(),
            lastSeenAt:
                DateTime.tryParse(msg['last_seen_at'] as String? ?? ''),
            distanceToHostM: (msg['distance_to_host_m'] as num?)?.toDouble(),
            distanceToDestinationM:
                (msg['distance_to_destination_m'] as num?)?.toDouble(),
          );
          if (userId == _meId && msg['status'] is String) {
            _myStatus = msg['status'] as String;
          }
        });
        if (_followMe && userId == _meId) _centerOnMe();
      case 'participant_joined':
        if (userId == null) return;
        final user = PublicUserDto.maybe(msg['user']);
        setState(() {
          _participants.putIfAbsent(
            userId,
            () => ParticipantDto(
              id: userId,
              rideId: widget.rideId,
              userId: userId,
              role: 'participant',
              status: 'joined',
              user: user,
            ),
          );
        });
        showRxToast(context, '${user?.displayName ?? 'A driver'} joined',
            icon: CupertinoIcons.person_badge_plus);
      case 'participant_left':
      case 'participant_removed':
        if (userId == null) return;
        if (userId == _meId && type == 'participant_removed') {
          _bg.stopRide();
          showRxToast(context, 'The host removed you from this drive.',
              isError: true);
          if (context.canPop()) context.pop();
          return;
        }
        setState(() => _participants.remove(userId));
      case 'ride_status':
        final status = msg['status'] as String?;
        if (status == null || _ride == null) return;
        setState(() => _ride = _ride!.copyWith(status: status));
        if (status == 'live') {
          HapticFeedback.mediumImpact();
          showRxToast(context, 'The drive has started',
              icon: CupertinoIcons.flag_fill);
          _startTracking();
        } else if (status == 'ended' || status == 'cancelled') {
          _bg.stopRide();
          showRxToast(
            context,
            status == 'ended' ? 'The drive has ended' : 'The drive was cancelled',
            icon: CupertinoIcons.flag_circle_fill,
          );
          _ws?.disconnect();
        }
        _invalidateLists();
    }
  }

  void _invalidateLists() {
    ref.invalidate(discoverRidesProvider);
    ref.invalidate(myRidesProvider);
  }

  // ── Camera ────────────────────────────────────────────────────────────────

  List<LatLng> get _allPoints => [
        for (final p in _participants.values)
          if (p.hasLocation) LatLng(p.lat!, p.lon!),
        if (_ride?.hasDestination ?? false)
          LatLng(_ride!.destLat!, _ride!.destLon!),
        if (_ride?.startLat != null && _ride?.startLon != null)
          LatLng(_ride!.startLat!, _ride!.startLon!),
      ];

  void _fitIfReady() {
    if (_fittedOnce || !_mapReady || _ride == null) return;
    _fittedOnce = true;
    _fitEveryone();
  }

  void _fitEveryone() {
    if (!_mapReady) return;
    final pts = _allPoints;
    if (pts.isEmpty) return;
    setState(() => _followMe = false);
    if (pts.length == 1) {
      _map.move(pts.first, 15);
      return;
    }
    _map.fitCamera(CameraFit.coordinates(
      coordinates: pts,
      padding: EdgeInsets.fromLTRB(
        60,
        MediaQuery.paddingOf(context).top + 90,
        60,
        MediaQuery.sizeOf(context).height * 0.36,
      ),
      maxZoom: 16,
    ));
  }

  void _centerOnMe() {
    final me = _participants[_meId];
    if (!_mapReady || me == null || !me.hasLocation) return;
    _map.move(LatLng(me.lat!, me.lon!), _map.camera.zoom < 14 ? 15 : _map.camera.zoom);
  }

  void _toggleFollow() {
    final me = _participants[_meId];
    if (me == null || !me.hasLocation) {
      showRxToast(context, 'Waiting for your location…',
          icon: CupertinoIcons.location);
      return;
    }
    setState(() => _followMe = !_followMe);
    if (_followMe) _centerOnMe();
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _run(Future<void> Function() action) async {
    if (_actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) showRxError(context, e);
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  Future<void> _start() => _run(() async {
        final ride =
            await ref.read(ridesRepositoryProvider).startRide(widget.rideId);
        if (!mounted) return;
        HapticFeedback.mediumImpact();
        setState(() => _ride = _mergeRide(ride));
        _invalidateLists();
        await _startTracking();
      });

  Future<void> _end() async {
    final ok = await confirmRx(
      context,
      title: 'End this drive?',
      message: 'Everyone will stop sharing their location.',
      confirmLabel: 'End Drive',
    );
    if (!ok || !mounted) return;
    await _run(() async {
      final ride =
          await ref.read(ridesRepositoryProvider).endRide(widget.rideId);
      await _bg.stopRide();
      if (!mounted) return;
      setState(() => _ride = _mergeRide(ride));
      _invalidateLists();
      showRxToast(context, 'Drive ended');
    });
  }

  Future<void> _cancel() async {
    final choice = await showRxActionSheet<bool>(
      context,
      title: 'Cancel this drive?',
      message: 'Participants will be notified that the drive is off.',
      actions: const [
        RxSheetAction(label: 'Cancel Drive', value: true, destructive: true),
      ],
    );
    if (choice != true || !mounted) return;
    await _run(() async {
      final ride =
          await ref.read(ridesRepositoryProvider).cancelRide(widget.rideId);
      if (!mounted) return;
      setState(() => _ride = _mergeRide(ride));
      _invalidateLists();
      showRxToast(context, 'Drive cancelled');
    });
  }

  Future<void> _leave() async {
    final ok = await confirmRx(
      context,
      title: 'Leave this drive?',
      message: 'You will stop sharing your location with the group.',
      confirmLabel: 'Leave',
    );
    if (!ok || !mounted) return;
    await _run(() async {
      await ref.read(ridesRepositoryProvider).leaveRide(widget.rideId);
      await _bg.stopRide();
      _invalidateLists();
      if (!mounted) return;
      showRxToast(context, 'You left the drive');
      context.pop();
    });
  }

  Future<void> _remove(ParticipantDto p) async {
    final ok = await confirmRx(
      context,
      title: 'Remove ${p.name}?',
      message: 'They will no longer see the group or share location.',
      confirmLabel: 'Remove',
    );
    if (!ok || !mounted) return;
    await _run(() async {
      await ref
          .read(ridesRepositoryProvider)
          .removeParticipant(widget.rideId, p.userId);
      if (!mounted) return;
      setState(() => _participants.remove(p.userId));
    });
  }

  Future<void> _setStatus(String status) async {
    final previous = _myStatus;
    HapticFeedback.selectionClick();
    setState(() => _myStatus = status);
    try {
      await ref
          .read(ridesRepositoryProvider)
          .updateMyStatus(widget.rideId, status);
      _bg.updateParticipantStatus(status);
    } catch (e) {
      if (!mounted) return;
      setState(() => _myStatus = previous);
      showRxError(context, e);
    }
  }

  RideDto _mergeRide(RideDto fresh) {
    if (fresh.participants.isNotEmpty) {
      for (final p in fresh.participants) {
        final live = _participants[p.userId];
        _participants[p.userId] = live == null
            ? p
            : p.copyWith(
                lat: live.lat ?? p.lat,
                lon: live.lon ?? p.lon,
                lastSeenAt: live.lastSeenAt ?? p.lastSeenAt,
              );
      }
    }
    return fresh;
  }

  void _shareInvite(RideDto ride) {
    Share.share(
      'Join my RideX drive "${ride.title}" with code ${ride.joinCode}',
      subject: 'RideX drive invite',
    );
  }

  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) showRxToast(context, 'Code copied');
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    if (_loading) {
      return CupertinoPageScaffold(
        backgroundColor: rx.background,
        child: const Center(child: CupertinoActivityIndicator(radius: 14)),
      );
    }
    if (_loadError != null || _ride == null) {
      return RxPage(
        title: 'Drive',
        child: Center(
          child: RxErrorState(
            error: _loadError ?? 'Drive not found',
            onRetry: _bootstrap,
          ),
        ),
      );
    }

    final ride = _ride!;
    final top = MediaQuery.paddingOf(context).top;

    return CupertinoPageScaffold(
      backgroundColor: rx.background,
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: _allPoints.isNotEmpty
                    ? _allPoints.first
                    : const LatLng(20.5937, 78.9629),
                initialZoom: _allPoints.isNotEmpty ? 14 : 4,
                onMapReady: () {
                  _mapReady = true;
                  _fitIfReady();
                },
                onPositionChanged: (_, hasGesture) {
                  if (hasGesture && _followMe) {
                    setState(() => _followMe = false);
                  }
                },
              ),
              children: [
                const RxTileLayer(),
                MarkerLayer(markers: _markers(ride)),
                const RxMapAttribution(),
              ],
            ),
            Positioned(
              top: top + 8,
              left: 12,
              right: 12,
              child: _topBar(ride),
            ),
            _sheet(ride),
          ],
        ),
      ),
    );
  }

  List<Marker> _markers(RideDto ride) {
    final rx = context.rx;
    final markers = <Marker>[];
    if (ride.hasDestination) {
      markers.add(Marker(
        point: LatLng(ride.destLat!, ride.destLon!),
        width: 40,
        height: 40,
        alignment: Alignment.topCenter,
        child: Semantics(
          label: 'Destination',
          child: Icon(CupertinoIcons.flag_fill, color: rx.accent, size: 34),
        ),
      ));
    }
    if (ride.startLat != null && ride.startLon != null && !ride.isLive) {
      markers.add(Marker(
        point: LatLng(ride.startLat!, ride.startLon!),
        width: 36,
        height: 36,
        child: Semantics(
          label: 'Meeting point',
          child: Icon(CupertinoIcons.location_solid,
              color: rx.success, size: 30),
        ),
      ));
    }
    final now = DateTime.now();
    for (final p in _participants.values) {
      if (!p.hasLocation) continue;
      final stale = p.lastSeenAt == null ||
          now.difference(p.lastSeenAt!.toLocal()).inMinutes >= 2;
      final ring = p.isHost ? rx.accent : rx.info;
      final isMe = p.userId == _meId;
      markers.add(Marker(
        point: LatLng(p.lat!, p.lon!),
        width: 64,
        height: 64,
        child: Opacity(
          opacity: stale ? 0.5 : 1,
          child: Semantics(
            label:
                '${isMe ? 'You' : p.name}${p.isHost ? ', host' : ''}, ${participantStatusLabel(p.status)}',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    color: ring,
                    shape: BoxShape.circle,
                    boxShadow: const [
                      BoxShadow(color: Color(0x40000000), blurRadius: 6),
                    ],
                  ),
                  child: RxAvatar(
                    name: p.name,
                    avatarPath: p.user?.avatarPath,
                    size: 34,
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: rx.cardElevated.withOpacity(0.92),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isMe ? 'You' : p.name.split(' ').first,
                    style: rx.caption2.copyWith(
                        color: rx.label, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ));
    }
    return markers;
  }

  Widget _topBar(RideDto ride) {
    final rx = context.rx;
    final wsState = _ws?.state.value;
    final reconnecting = _ws != null &&
        !ride.isOver &&
        wsState != WsConnectionState.connected;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RxMapButton(
          icon: CupertinoIcons.chevron_back,
          semanticLabel: 'Back',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/rides');
            }
          },
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: rx.cardElevated.withOpacity(0.94),
              borderRadius: BorderRadius.circular(22),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x29000000),
                    blurRadius: 12,
                    offset: Offset(0, 4)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  ride.title,
                  style: rx.headline,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RxRideStatusPill(status: ride.status),
                    if (reconnecting) ...[
                      const SizedBox(width: 6),
                      RxPill(
                        label: wsState == WsConnectionState.connecting
                            ? 'Connecting…'
                            : 'Reconnecting…',
                        color: rx.warning,
                        icon: CupertinoIcons.wifi_exclamationmark,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Column(
          children: [
            RxMapButton(
              icon: CupertinoIcons.person_2_fill,
              semanticLabel: 'Show everyone',
              onPressed: _fitEveryone,
            ),
            const SizedBox(height: 8),
            RxMapButton(
              icon: _followMe
                  ? CupertinoIcons.location_fill
                  : CupertinoIcons.location,
              semanticLabel: _followMe ? 'Stop following me' : 'Follow me',
              active: _followMe,
              onPressed: _toggleFollow,
            ),
          ],
        ),
      ],
    );
  }

  Widget _sheet(RideDto ride) {
    final rx = context.rx;
    return DraggableScrollableSheet(
      minChildSize: 0.22,
      initialChildSize: 0.32,
      maxChildSize: 0.85,
      snap: true,
      snapSizes: const [0.32],
      builder: (context, controller) {
        return Container(
          decoration: BoxDecoration(
            color: rx.background,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(16)),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 20,
                  offset: Offset(0, -4)),
            ],
          ),
          child: ListView(
            controller: controller,
            padding: EdgeInsets.only(
                bottom: MediaQuery.paddingOf(context).bottom + RxSpace.l),
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 8, bottom: 12),
                  width: 36,
                  height: 5,
                  decoration: BoxDecoration(
                    color: rx.tertiaryLabel,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              ..._sheetContent(ride),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _sheetContent(RideDto ride) {
    final rx = context.rx;
    const pad = EdgeInsets.symmetric(horizontal: RxSpace.inset);
    final participants = _participants.values.toList()
      ..sort((a, b) {
        if (a.isHost != b.isHost) return a.isHost ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    return [
      if (ride.isOver)
        Padding(
          padding: pad,
          child: RxCard(
            child: Row(
              children: [
                Icon(CupertinoIcons.flag_circle_fill,
                    color: rx.gray, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    ride.status == 'cancelled'
                        ? 'This drive was cancelled'
                        : 'This drive has ended',
                    style: rx.headline,
                  ),
                ),
              ],
            ),
          ),
        ),
      if (_permissionWarning && !ride.isOver) ...[
        Padding(
          padding: pad,
          child: RxCard(
            color: rx.warning.withOpacity(rx.isDark ? 0.22 : 0.14),
            child: Row(
              children: [
                Icon(CupertinoIcons.location_slash_fill,
                    color: rx.warning, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Location permission needed to share your position.',
                    style: rx.subheadline.copyWith(color: rx.label),
                  ),
                ),
                RxButton.plain(
                  label: 'Open Settings',
                  onPressed: () async {
                    await Geolocator.openAppSettings();
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: RxSpace.m),
      ],
      if (!ride.isOver && !_isParticipant) ...[
        Padding(
          padding: pad,
          child: RxCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Want to drive along?', style: rx.headline),
                const SizedBox(height: 4),
                Text('Ask the host for the join code.',
                    style: rx.subheadline),
                const SizedBox(height: 12),
                RxButton.tinted(
                  label: 'Enter Code',
                  icon: CupertinoIcons.qrcode,
                  onPressed: () => context.push('/rides/join'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: RxSpace.m),
      ],
      if (!ride.isOver && _isHost) ...[
        Padding(
          padding: pad,
          child: ride.isScheduled
              ? Column(
                  children: [
                    RxButton(
                      label: 'Start Drive',
                      icon: CupertinoIcons.play_fill,
                      busy: _actionBusy,
                      onPressed: _start,
                    ),
                    const SizedBox(height: 4),
                    RxButton.plain(
                      label: 'Cancel Drive',
                      onPressed: _actionBusy ? null : _cancel,
                    ),
                  ],
                )
              : RxButton(
                  kind: RxButtonKind.destructive,
                  label: 'End Drive',
                  icon: CupertinoIcons.stop_fill,
                  busy: _actionBusy,
                  onPressed: _end,
                ),
        ),
        const SizedBox(height: RxSpace.m),
      ],
      if (ride.isScheduled && _isParticipant && !_isHost) ...[
        Padding(
          padding: pad,
          child: RxCard(
            child: Row(
              children: [
                Icon(CupertinoIcons.clock, color: rx.info, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    ride.scheduledAt != null
                        ? 'Starts ${formatRideTime(ride.scheduledAt!)}. Location sharing begins when the host starts the drive.'
                        : 'Location sharing begins when the host starts the drive.',
                    style: rx.subheadline.copyWith(color: rx.label),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: RxSpace.m),
      ],
      if (ride.isLive && _isParticipant) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(
              RxSpace.inset + 16, 0, RxSpace.inset, RxSpace.s),
          child: Text('MY STATUS', style: rx.footnote),
        ),
        Padding(
          padding: pad,
          child: SizedBox(
            width: double.infinity,
            child: CupertinoSlidingSegmentedControl<String>(
              groupValue:
                  participantStatuses.contains(_myStatus) ? _myStatus : null,
              children: {
                for (final s in participantStatuses)
                  s: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      participantStatusLabel(s),
                      style: rx.footnote.copyWith(
                          color: rx.label, fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              },
              onValueChanged: (v) {
                if (v != null && v != _myStatus) _setStatus(v);
              },
            ),
          ),
        ),
        const SizedBox(height: RxSpace.m),
      ],
      if (ride.joinCode != null && !ride.isOver) ...[
        Padding(
          padding: pad,
          child: RxCard(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Invite code', style: rx.footnote),
                      const SizedBox(height: 2),
                      Semantics(
                        label: 'Invite code ${ride.joinCode!.split('').join(' ')}',
                        excludeSemantics: true,
                        child: Text(
                          ride.joinCode!,
                          style: rx.numeric(28).copyWith(letterSpacing: 4),
                        ),
                      ),
                    ],
                  ),
                ),
                RxNavIconButton(
                  icon: CupertinoIcons.doc_on_doc,
                  semanticLabel: 'Copy code',
                  onPressed: () => _copyCode(ride.joinCode!),
                ),
                RxNavIconButton(
                  icon: CupertinoIcons.share,
                  semanticLabel: 'Share invite',
                  onPressed: () => _shareInvite(ride),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: RxSpace.m),
      ],
      if (ride.description != null && ride.description!.isNotEmpty) ...[
        Padding(
          padding: pad,
          child: Text(ride.description!, style: rx.subheadline),
        ),
        const SizedBox(height: RxSpace.m),
      ],
      RxSection(
        header: 'Drivers (${participants.length})',
        children: [
          for (final p in participants) _participantTile(ride, p),
        ],
      ),
      if (!ride.isOver && _isParticipant && !_isHost) ...[
        const SizedBox(height: RxSpace.s),
        Padding(
          padding: pad,
          child: RxButton.plain(
            label: 'Leave Drive',
            expand: true,
            onPressed: _actionBusy ? null : _leave,
          ),
        ),
      ],
    ];
  }

  Widget _participantTile(RideDto ride, ParticipantDto p) {
    final rx = context.rx;
    final isMe = p.userId == _meId;
    final parts = <String>[participantStatusLabel(p.status)];
    if (!p.isHost && p.distanceToHostM != null) {
      parts.add('${formatDistanceMeters(p.distanceToHostM)} from host');
    }
    if (ride.hasDestination && p.distanceToDestinationM != null) {
      parts.add('${formatDistanceMeters(p.distanceToDestinationM)} to go');
    }
    if (ride.isLive) parts.add(relativeTime(p.lastSeenAt));

    final canRemove = _isHost && !isMe && !ride.isOver;
    return RxTile(
      title: isMe ? '${p.name} (You)' : p.name,
      subtitle: parts.join(' · '),
      leading: RxAvatar(name: p.name, avatarPath: p.user?.avatarPath, size: 36),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (p.isHost) RxPill(label: 'Host', color: rx.accent),
          if (canRemove)
            RxNavIconButton(
              icon: CupertinoIcons.ellipsis_circle,
              semanticLabel: 'Options for ${p.name}',
              onPressed: () async {
                final choice = await showRxActionSheet<String>(
                  context,
                  title: p.name,
                  actions: const [
                    RxSheetAction(
                      label: 'Remove from Drive',
                      value: 'remove',
                      destructive: true,
                    ),
                  ],
                );
                if (choice == 'remove') _remove(p);
              },
            ),
        ],
      ),
      onTap: p.hasLocation
          ? () {
              setState(() => _followMe = false);
              _map.move(LatLng(p.lat!, p.lon!), 16);
            }
          : null,
      chevron: false,
    );
  }
}
