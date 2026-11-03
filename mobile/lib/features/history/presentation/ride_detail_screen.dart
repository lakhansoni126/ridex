import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../../database/models.dart';
import '../../../main.dart';
import '../../../services/export_service.dart';
import '../../../shared/ui/ui.dart';
import '../../map/domain/polyline_engine.dart';
import '../../ride/presentation/home_dashboard_screen.dart';
import 'history_screen.dart';

final rideDetailProvider =
    FutureProvider.autoDispose.family<Ride?, int>((ref, id) {
  return dbService.getRideById(id);
});

enum _Action { replay, export, delete }

/// Route map (coloured by speed) + full stats for one local drive.
class RideDetailScreen extends ConsumerWidget {
  const RideDetailScreen({super.key, required this.rideId});

  final int rideId;

  Future<void> _more(BuildContext context, WidgetRef ref, Ride ride) async {
    final action = await showRxActionSheet<_Action>(
      context,
      actions: const [
        RxSheetAction(label: 'Replay Drive', value: _Action.replay),
        RxSheetAction(label: 'Export as JSON', value: _Action.export),
        RxSheetAction(
            label: 'Delete Drive', value: _Action.delete, destructive: true),
      ],
    );
    if (!context.mounted || action == null) return;
    switch (action) {
      case _Action.replay:
        context.push('/drive/ride/$rideId/replay');
      case _Action.export:
        try {
          await ExportService.exportRideToJson(ride);
        } catch (e) {
          if (context.mounted) showRxError(context, e);
        }
      case _Action.delete:
        final ok = await confirmRx(
          context,
          title: 'Delete This Drive?',
          message: 'This can\'t be undone.',
          confirmLabel: 'Delete',
        );
        if (!ok) return;
        await dbService.deleteRide(rideId);
        ref.invalidate(historyProvider);
        ref.invalidate(driveStatsProvider);
        if (context.mounted) context.pop();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rx = context.rx;
    final async = ref.watch(rideDetailProvider(rideId));

    return async.when(
      loading: () => const RxPage(
        title: 'Drive',
        child: Center(child: CupertinoActivityIndicator()),
      ),
      error: (e, _) => RxPage(
        title: 'Drive',
        child: Center(child: RxErrorState(error: e)),
      ),
      data: (ride) {
        if (ride == null) {
          return const RxPage(
            title: 'Drive',
            child: Center(
              child: RxEmptyState(
                icon: CupertinoIcons.question_circle,
                title: 'Drive Not Found',
                message: 'It may have been deleted.',
              ),
            ),
          );
        }
        final points = ride.points.toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
        final bounds = PolylineEngine.bounds(points);
        final polylines = PolylineEngine.generateHeatmap(points);
        final mapHeight = MediaQuery.sizeOf(context).height * 0.42;

        return CupertinoPageScaffold(
          backgroundColor: rx.background,
          child: Material(
            type: MaterialType.transparency,
            child: Stack(
              children: [
                CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: mapHeight,
                        child: points.isEmpty
                            ? Container(
                                color: rx.fill,
                                alignment: Alignment.center,
                                child: Text('No GPS points recorded',
                                    style: rx.subheadline),
                              )
                            : FlutterMap(
                                options: MapOptions(
                                  initialCameraFit: CameraFit.bounds(
                                    bounds: bounds!,
                                    padding: const EdgeInsets.fromLTRB(
                                        40, 100, 40, 40),
                                    maxZoom: 17,
                                  ),
                                  interactionOptions: const InteractionOptions(
                                    flags: InteractiveFlag.all &
                                        ~InteractiveFlag.rotate,
                                  ),
                                ),
                                children: [
                                  const RxTileLayer(),
                                  PolylineLayer(polylines: polylines),
                                  MarkerLayer(markers: [
                                    _endpoint(points.first, rx.success,
                                        CupertinoIcons.flag_fill),
                                    _endpoint(points.last, rx.destructive,
                                        CupertinoIcons.flag_circle_fill),
                                  ]),
                                  const RxMapAttribution(),
                                ],
                              ),
                      ),
                    ),
                    RxSliverPadding(
                      top: RxSpace.l,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(DateFormat('EEEE, MMM d').format(ride.startTime),
                              style: rx.title2),
                          const SizedBox(height: 2),
                          Text(
                            '${DateFormat('h:mm a').format(ride.startTime)}'
                            '${ride.endTime != null ? ' – ${DateFormat('h:mm a').format(ride.endTime!)}' : ''}'
                            '${ride.weatherCondition != null ? ' · ${ride.temperatureCelsius?.toStringAsFixed(0) ?? '--'}°C ${ride.weatherCondition}' : ''}',
                            style: rx.subheadline,
                          ),
                        ],
                      ),
                    ),
                    RxSliverPadding(
                      top: RxSpace.m,
                      child: RxCard(
                        padding: const EdgeInsets.all(RxSpace.m + 4),
                        child: RxMetricGrid(metrics: [
                          RxMetric(
                            label: 'Distance',
                            value: ride.distance.toStringAsFixed(2),
                            unit: 'km',
                            icon: CupertinoIcons.map_fill,
                            iconColor: rx.info,
                          ),
                          RxMetric(
                            label: 'Duration',
                            value:
                                formatDuration(ride.durationSeconds.toInt()),
                            icon: CupertinoIcons.timer,
                            iconColor: rx.indigo,
                          ),
                          RxMetric(
                            label: 'Average',
                            value: ride.avgSpeed.toStringAsFixed(0),
                            unit: 'km/h',
                            icon: CupertinoIcons.gauge,
                            iconColor: rx.teal,
                          ),
                          RxMetric(
                            label: 'Top Speed',
                            value: ride.topSpeed.toStringAsFixed(0),
                            unit: 'km/h',
                            icon: CupertinoIcons.bolt_fill,
                            iconColor: rx.warning,
                          ),
                        ]),
                      ),
                    ),
                    RxSliverPadding(
                      top: RxSpace.m,
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 6,
                        children: [
                          for (final b in PolylineEngine.bands)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                      color: b.color, shape: BoxShape.circle),
                                ),
                                const SizedBox(width: 4),
                                Text('${b.label} km/h', style: rx.caption),
                              ],
                            ),
                        ],
                      ),
                    ),
                    RxSliverPadding(
                      top: RxSpace.l,
                      child: RxButton.tinted(
                        label: 'Replay Drive',
                        icon: CupertinoIcons.play_fill,
                        onPressed: points.length < 2
                            ? null
                            : () => context.push('/drive/ride/$rideId/replay'),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: SizedBox(
                          height: MediaQuery.paddingOf(context).bottom +
                              RxSpace.l),
                    ),
                  ],
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(RxSpace.s + 4),
                    child: Row(
                      children: [
                        RxMapButton(
                          icon: CupertinoIcons.chevron_back,
                          semanticLabel: 'Back',
                          onPressed: () => context.pop(),
                        ),
                        const Spacer(),
                        RxMapButton(
                          icon: CupertinoIcons.ellipsis,
                          semanticLabel: 'More actions',
                          onPressed: () => _more(context, ref, ride),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Marker _endpoint(RidePoint p, Color color, IconData icon) => Marker(
        point: LatLng(p.latitude, p.longitude),
        width: 30,
        height: 30,
        child: Container(
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFFFFFFF), width: 2.5),
            boxShadow: const [
              BoxShadow(color: Color(0x40000000), blurRadius: 6),
            ],
          ),
          child: Icon(icon, size: 14, color: const Color(0xFFFFFFFF)),
        ),
      );
}
