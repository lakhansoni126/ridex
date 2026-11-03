import 'package:flutter/cupertino.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/providers.dart';
import '../../../data/api/shares_repository.dart';
import '../../../data/ws/ws_client.dart';
import '../../../shared/ui/ui.dart';
import 'location_sharing_screen.dart';

/// Full-screen live map of every friend currently sharing with me.
class FriendsMapScreen extends ConsumerStatefulWidget {
  const FriendsMapScreen({super.key});

  @override
  ConsumerState<FriendsMapScreen> createState() => _FriendsMapScreenState();
}

class _FriendsMapScreenState extends ConsumerState<FriendsMapScreen> {
  final MapController _map = MapController();
  final Map<String, LocationShareDto> _shares = {};
  LocationShareWsSession? _ws;
  Position? _me;
  bool _loading = true;
  Object? _error;
  bool _mapReady = false;
  bool _fittedOnce = false;
  String? _focusedShareId;

  @override
  void initState() {
    super.initState();
    _load();
    _connect();
    _loadMyPosition();
  }

  @override
  void dispose() {
    _ws?.disconnect();
    _map.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await ref.read(sharesRepositoryProvider).listShares();
      if (!mounted) return;
      setState(() {
        _shares
          ..clear()
          ..addEntries(list.sharedWithMe.map((s) => MapEntry(s.id, s)));
        _loading = false;
        _error = null;
      });
      _fitAll(animate: false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  Future<void> _connect() async {
    final ws = LocationShareWsSession(
      tokenProvider: ref.read(tokenStoreProvider).readAccessToken,
    );
    _ws = ws;
    await ws.connect(onMessage: _onMessage);
  }

  Future<void> _loadMyPosition() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getLastKnownPosition();
      if (mounted && pos != null) setState(() => _me = pos);
    } catch (_) {}
  }

  void _onMessage(Map<String, dynamic> msg) {
    if (!mounted) return;
    switch (msg['type']) {
      case 'friend_location':
        final id = msg['share_id'] as String?;
        final lat = (msg['lat'] as num?)?.toDouble();
        final lon = (msg['lon'] as num?)?.toDouble();
        if (id == null || lat == null || lon == null) return;
        final existing = _shares[id];
        if (existing == null) {
          // A share we don't know yet (just started): reload metadata.
          _load();
          return;
        }
        setState(() {
          _shares[id] = existing.copyWith(
            lat: lat,
            lon: lon,
            lastSeenAt:
                DateTime.tryParse(msg['last_seen_at'] as String? ?? '') ??
                    DateTime.now(),
          );
        });
        if (!_fittedOnce) _fitAll();
      case 'share_ended':
        final id = msg['share_id'] as String?;
        if (id != null && _shares.containsKey(id)) {
          setState(() => _shares.remove(id));
          ref.invalidate(locationSharesProvider);
        }
    }
  }

  List<LocationShareDto> get _located =>
      _shares.values.where((s) => s.hasLocation).toList();

  void _fitAll({bool animate = true}) {
    if (!_mapReady) return;
    final points = [
      for (final s in _located) LatLng(s.lat!, s.lon!),
    ];
    if (points.isEmpty) return;
    _fittedOnce = true;
    if (points.length == 1) {
      _map.move(points.first, 15);
      return;
    }
    _map.fitCamera(CameraFit.coordinates(
      coordinates: points,
      padding: const EdgeInsets.fromLTRB(60, 120, 60, 280),
      maxZoom: 16,
    ));
  }

  void _focus(LocationShareDto s) {
    if (!s.hasLocation || !_mapReady) return;
    setState(() => _focusedShareId = s.id);
    _map.move(LatLng(s.lat!, s.lon!), 16);
  }

  String? _distanceFromMe(LocationShareDto s) {
    final me = _me;
    if (me == null || !s.hasLocation) return null;
    final m =
        Geolocator.distanceBetween(me.latitude, me.longitude, s.lat!, s.lon!);
    return formatDistanceMeters(m);
  }

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final topInset = MediaQuery.paddingOf(context).top;
    final located = _located;

    final initialCenter = located.isNotEmpty
        ? LatLng(located.first.lat!, located.first.lon!)
        : _me != null
            ? LatLng(_me!.latitude, _me!.longitude)
            : const LatLng(20.5937, 78.9629);

    return CupertinoPageScaffold(
      backgroundColor: rx.background,
      child: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: initialCenter,
              initialZoom: located.isNotEmpty || _me != null ? 13 : 4,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onMapReady: () {
                _mapReady = true;
                _fitAll(animate: false);
              },
            ),
            children: [
              const RxTileLayer(),
              MarkerLayer(
                markers: [
                  if (_me != null)
                    Marker(
                      point: LatLng(_me!.latitude, _me!.longitude),
                      width: 22,
                      height: 22,
                      child: _MeDot(color: rx.info),
                    ),
                  for (final s in located)
                    Marker(
                      point: LatLng(s.lat!, s.lon!),
                      width: 120,
                      height: 76,
                      alignment: Alignment.topCenter,
                      child: GestureDetector(
                        onTap: () => _focus(s),
                        child: _FriendMarker(
                          share: s,
                          focused: s.id == _focusedShareId,
                        ),
                      ),
                    ),
                ],
              ),
              const RxMapAttribution(),
            ],
          ),

          // ── Top controls ──
          Positioned(
            top: topInset + RxSpace.s,
            left: RxSpace.m,
            child: RxMapButton(
              icon: CupertinoIcons.xmark,
              semanticLabel: 'Close map',
              onPressed: () => context.pop(),
            ),
          ),
          Positioned(
            top: topInset + RxSpace.s,
            right: RxSpace.m,
            child: Column(
              children: [
                RxMapButton(
                  icon: CupertinoIcons.person_2_fill,
                  semanticLabel: 'Show all friends',
                  onPressed: _fitAll,
                ),
                if (_me != null) ...[
                  const SizedBox(height: RxSpace.s),
                  RxMapButton(
                    icon: CupertinoIcons.location_fill,
                    semanticLabel: 'Show my location',
                    onPressed: () {
                      if (_mapReady) {
                        _map.move(LatLng(_me!.latitude, _me!.longitude), 15);
                      }
                    },
                  ),
                ],
              ],
            ),
          ),

          // ── Bottom sheet ──
          Align(
            alignment: Alignment.bottomCenter,
            child: _BottomSheet(child: _sheetContent(located)),
          ),
        ],
      ),
    );
  }

  Widget _sheetContent(List<LocationShareDto> located) {
    final rx = context.rx;
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(RxSpace.l),
        child: CupertinoActivityIndicator(),
      );
    }
    if (_error != null) {
      return RxErrorState(
        error: _error!,
        onRetry: () {
          setState(() => _loading = true);
          _load();
        },
      );
    }
    if (_shares.isEmpty) {
      return RxEmptyState(
        icon: CupertinoIcons.map,
        title: 'Nobody is sharing',
        message:
            "When friends share their location with you, they'll appear here live.",
        actionLabel: 'Share My Location',
        onAction: () => context.push('/friends/sharing'),
      );
    }
    final all = _shares.values.toList()
      ..sort((a, b) =>
          (b.lastSeenAt ?? DateTime(0)).compareTo(a.lastSeenAt ?? DateTime(0)));
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.38,
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(RxSpace.m, 0, RxSpace.m, RxSpace.m),
        itemCount: all.length,
        separatorBuilder: (_, __) => Container(
          margin: const EdgeInsets.only(left: 56),
          height: 0.5,
          color: rx.separator,
        ),
        itemBuilder: (context, i) {
          final s = all[i];
          final name = s.owner?.displayName ?? 'Friend';
          final dist = _distanceFromMe(s);
          final subtitle = s.hasLocation
              ? [
                  'Updated ${relativeTime(s.lastSeenAt)}',
                  if (dist != null) '$dist away',
                ].join(' · ')
              : 'Waiting for location…';
          return RxPressable(
            onTap: () => _focus(s),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  RxAvatar(name: name, avatarPath: s.owner?.avatarPath),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: rx.headline),
                        const SizedBox(height: 2),
                        Text(subtitle, style: rx.footnote),
                      ],
                    ),
                  ),
                  if (s.hasLocation)
                    Icon(CupertinoIcons.location_fill,
                        size: 16, color: rx.accent),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BottomSheet extends StatelessWidget {
  const _BottomSheet({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: rx.card,
        borderRadius: const BorderRadius.vertical(
            top: Radius.circular(RxSpace.radiusLarge)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x33000000), blurRadius: 20, offset: Offset(0, -4)),
        ],
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: RxSpace.s),
            width: 36,
            height: 5,
            decoration: BoxDecoration(
              color: rx.tertiaryLabel,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _FriendMarker extends StatelessWidget {
  const _FriendMarker({required this.share, required this.focused});

  final LocationShareDto share;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    final name = share.owner?.displayName ?? 'Friend';
    final stale = share.lastSeenAt == null ||
        DateTime.now().difference(share.lastSeenAt!.toLocal()).inMinutes > 10;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: focused ? rx.accent : const Color(0xFFFFFFFF),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x40000000),
                  blurRadius: 6,
                  offset: Offset(0, 2)),
            ],
          ),
          child: Opacity(
            opacity: stale ? 0.55 : 1,
            child: RxAvatar(
                name: name, avatarPath: share.owner?.avatarPath, size: 40),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          constraints: const BoxConstraints(maxWidth: 116),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: rx.cardElevated.withOpacity(0.95),
            borderRadius: BorderRadius.circular(100),
          ),
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: rx.caption.copyWith(
              color: rx.label,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _MeDot extends StatelessWidget {
  const _MeDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: const Color(0xFFFFFFFF), width: 3),
        boxShadow: const [
          BoxShadow(color: Color(0x40000000), blurRadius: 6),
        ],
      ),
    );
  }
}
