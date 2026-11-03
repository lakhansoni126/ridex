import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/api/rides_repository.dart';
import '../../../data/ws/ws_client.dart';
import '../../../features/auth/application/auth_notifier.dart';
import '../../../shared/widgets/glass.dart';

class LiveRideMapScreen extends ConsumerStatefulWidget {
  const LiveRideMapScreen({super.key, required this.rideId});

  final String rideId;

  @override
  ConsumerState<LiveRideMapScreen> createState() => _LiveRideMapScreenState();
}

class _LiveRideMapScreenState extends ConsumerState<LiveRideMapScreen> {
  final MapController _mapController = MapController();
  RideDto? _ride;
  final Map<String, ParticipantDto> _participants = {};
  RideWsSession? _ws;
  String? _error;
  bool _loading = true;
  bool _isHost = false;
  String _myStatus = 'joined';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final repo = ref.read(ridesRepositoryProvider);
      final ride = await repo.getRide(widget.rideId);
      final me = ref.read(authNotifierProvider).user;
      final token = await ref.read(tokenStoreProvider).readAccessToken();
      if (!mounted) return;

      setState(() {
        _ride = ride;
        _isHost = me != null && me.id == ride.hostId;
        for (final p in ride.participants) {
          _participants[p.userId] = p;
          if (me != null && p.userId == me.id) _myStatus = p.status;
        }
        _loading = false;
      });

      if (token == null) return;

      final ws = RideWsSession(rideId: widget.rideId, accessToken: token);
      _ws = ws;
      await ws.connect(
        onMessage: _onWsMessage,
        onError: (e) => debugPrint('Ride WS error: $e'),
      );

      final bg = ref.read(backgroundLocationServiceProvider);
      if (ride.status == 'live') {
        await bg.startForRide(
          rideId: ride.id,
          status: _myStatus == 'joined' ? 'riding' : _myStatus,
          ws: ws,
        );
      } else {
        bg.attachRideWs(ws);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _onWsMessage(Map<String, dynamic> msg) {
    final type = msg['type'] as String?;
    if (type == 'participant_update') {
      final userId = msg['user_id'] as String;
      final existing = _participants[userId];
      final updated = (existing ??
              ParticipantDto(
                id: userId,
                rideId: widget.rideId,
                userId: userId,
                role: 'participant',
                status: msg['status'] as String? ?? 'riding',
              ))
          .copyWith(
        status: msg['status'] as String?,
        lat: (msg['lat'] as num?)?.toDouble(),
        lon: (msg['lon'] as num?)?.toDouble(),
        lastSeenAt: msg['last_seen_at'] != null
            ? DateTime.tryParse(msg['last_seen_at'] as String)
            : null,
        distanceToHostM: (msg['distance_to_host_m'] as num?)?.toDouble(),
        distanceToDestinationM:
            (msg['distance_to_destination_m'] as num?)?.toDouble(),
      );
      setState(() => _participants[userId] = updated);
    } else if (type == 'ride_status') {
      final status = msg['status'] as String?;
      if (status != null && _ride != null) {
        setState(() {
          _ride = RideDto(
            id: _ride!.id,
            hostId: _ride!.hostId,
            title: _ride!.title,
            description: _ride!.description,
            visibility: _ride!.visibility,
            status: status,
            joinCode: _ride!.joinCode,
            inviteToken: _ride!.inviteToken,
            scheduledAt: _ride!.scheduledAt,
            startedAt: _ride!.startedAt,
            endedAt: _ride!.endedAt,
            startLat: _ride!.startLat,
            startLon: _ride!.startLon,
            destLat: _ride!.destLat,
            destLon: _ride!.destLon,
            participants: _participants.values.toList(),
          );
        });
        if (status == 'ended' || status == 'cancelled') {
          ref.read(backgroundLocationServiceProvider).stopRide();
        }
      }
    } else if (type == 'participant_removed') {
      final userId = msg['user_id'] as String?;
      if (userId != null) {
        setState(() => _participants.remove(userId));
      }
    }
  }

  Future<void> _startRide() async {
    final ride =
        await ref.read(ridesRepositoryProvider).startRide(widget.rideId);
    final bg = ref.read(backgroundLocationServiceProvider);
    await bg.startForRide(
      rideId: ride.id,
      status: 'riding',
      ws: _ws,
    );
    setState(() {
      _ride = ride;
      _myStatus = 'riding';
    });
  }

  Future<void> _endRide() async {
    final ride = await ref.read(ridesRepositoryProvider).endRide(widget.rideId);
    await ref.read(backgroundLocationServiceProvider).stopRide();
    setState(() => _ride = ride);
  }

  Future<void> _setStatus(String status) async {
    await ref
        .read(ridesRepositoryProvider)
        .updateMyStatus(widget.rideId, status);
    ref
        .read(backgroundLocationServiceProvider)
        .updateParticipantStatus(status);
    _ws?.sendStatus(status);
    setState(() => _myStatus = status);
  }

  @override
  void dispose() {
    _ws?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const GlassScaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null || _ride == null) {
      return GlassScaffold(
        appBar: const GlassAppBar(title: 'Drive'),
        body: Center(child: Text(_error ?? 'Not found')),
      );
    }

    final markers = <Marker>[];
    for (final p in _participants.values) {
      if (p.lat == null || p.lon == null) continue;
      markers.add(
        Marker(
          point: LatLng(p.lat!, p.lon!),
          width: 48,
          height: 48,
          child: Column(
            children: [
              Icon(
                Icons.navigation,
                color: p.role == 'host' ? AppTheme.accent : Colors.lightBlue,
                size: 28,
              ),
              Flexible(
                child: Text(
                  p.displayName ?? p.username ?? 'Driver',
                  style: const TextStyle(fontSize: 9, color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    }

    LatLng center = const LatLng(20.0, 0.0);
    if (markers.isNotEmpty) {
      center = markers.first.point;
    } else if (_ride!.startLat != null && _ride!.startLon != null) {
      center = LatLng(_ride!.startLat!, _ride!.startLon!);
    }

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: 14,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'ridex',
              ),
              MarkerLayer(markers: markers),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  GlassContainer(
                    variant: GlassVariant.mapOverlay,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    borderRadius: 16,
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_ride!.title,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600)),
                              Text(
                                '${_ride!.status.toUpperCase()} · code ${_ride!.joinCode}',
                                style: const TextStyle(
                                    color: AppTheme.textSecondary, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  GlassContainer(
                    variant: GlassVariant.mapOverlay,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          height: 72,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: _participants.values.map((p) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child: Column(
                                  children: [
                                    CircleAvatar(
                                      backgroundColor: AppTheme.surface,
                                      child: Text(
                                        ((p.displayName ?? p.username ?? '?')
                                                .isNotEmpty
                                            ? (p.displayName ??
                                                    p.username ??
                                                    '?')[0]
                                            : '?')
                                            .toUpperCase(),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      p.status,
                                      style: const TextStyle(
                                          fontSize: 10,
                                          color: AppTheme.textSecondary),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_isHost && _ride!.status == 'scheduled')
                          GlassButton(
                            label: 'START DRIVE',
                            onPressed: _startRide,
                          ),
                        if (_isHost && _ride!.status == 'live')
                          GlassButton(
                            label: 'END DRIVE',
                            onPressed: _endRide,
                          ),
                        if (_ride!.status == 'live') ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              for (final s in const [
                                'on_the_way',
                                'riding',
                                'paused',
                                'reached',
                              ])
                                ChoiceChip(
                                  label: Text(s.replaceAll('_', ' ')),
                                  selected: _myStatus == s,
                                  onSelected: (_) => _setStatus(s),
                                  selectedColor: AppTheme.accent,
                                  labelStyle: TextStyle(
                                    color: _myStatus == s
                                        ? Colors.white
                                        : Colors.white70,
                                  ),
                                  backgroundColor: AppTheme.surface,
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
