import 'package:flutter/cupertino.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/providers.dart';
import '../../../data/api/rides_repository.dart';
import '../../../shared/ui/ui.dart';
import 'rides_screen.dart';

class CreateRideScreen extends ConsumerStatefulWidget {
  const CreateRideScreen({super.key});

  @override
  ConsumerState<CreateRideScreen> createState() => _CreateRideScreenState();
}

class _CreateRideScreenState extends ConsumerState<CreateRideScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  String _visibility = 'public';
  bool _schedule = false;
  DateTime? _scheduledAt;
  LatLng? _start;
  LatLng? _destination;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _title.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  DateTime get _minDate =>
      DateTime.now().add(const Duration(minutes: 5));

  Future<void> _pickDate() async {
    var picked = _scheduledAt ?? _minDate.add(const Duration(minutes: 55));
    if (picked.isBefore(_minDate)) picked = _minDate;
    final result = await showCupertinoModalPopup<DateTime>(
      context: context,
      builder: (ctx) {
        final rx = ctx.rx;
        var value = picked;
        return Container(
          height: 320,
          color: rx.cardElevated,
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    RxNavTextButton(
                      label: 'Cancel',
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                    RxNavTextButton(
                      label: 'Done',
                      bold: true,
                      onPressed: () => Navigator.of(ctx).pop(value),
                    ),
                  ],
                ),
                Expanded(
                  child: CupertinoDatePicker(
                    initialDateTime: picked,
                    minimumDate: _minDate.subtract(const Duration(minutes: 1)),
                    maximumDate: DateTime.now().add(const Duration(days: 365)),
                    minuteInterval: 1,
                    use24hFormat: MediaQuery.of(ctx).alwaysUse24HourFormat,
                    onDateTimeChanged: (d) => value = d,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (result != null && mounted) setState(() => _scheduledAt = result);
  }

  Future<void> _pickLocation({required bool destination}) async {
    final result = await Navigator.of(context).push<LatLng>(
      CupertinoPageRoute(
        fullscreenDialog: true,
        builder: (_) => MapPointPickerScreen(
          title: destination ? 'Destination' : 'Meeting Point',
          initial: destination ? _destination : _start,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (destination) {
        _destination = result;
      } else {
        _start = result;
      }
    });
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (_title.text.trim().isEmpty) {
      showRxToast(context, 'Give your drive a title.', isError: true);
      return;
    }
    if (!(_formKey.currentState?.validate() ?? true)) return;
    if (_schedule && _scheduledAt == null) {
      showRxToast(context, 'Pick a start time or turn off scheduling.',
          isError: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final desc = _description.text.trim();
      final ride = await ref.read(ridesRepositoryProvider).createRide(
            title: _title.text.trim(),
            description: desc.isEmpty ? null : desc,
            visibility: _visibility,
            scheduledAt: _schedule ? _scheduledAt : null,
            start: _start == null
                ? null
                : GeoPointDto(lat: _start!.latitude, lon: _start!.longitude),
            destination: _destination == null
                ? null
                : GeoPointDto(
                    lat: _destination!.latitude,
                    lon: _destination!.longitude),
          );
      ref.invalidate(discoverRidesProvider);
      ref.invalidate(myRidesProvider);
      if (!mounted) return;
      showRxToast(context, 'Drive created');
      context.pushReplacement('/rides/live/${ride.id}');
    } catch (e) {
      if (mounted) showRxError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    return RxPage(
      title: 'New Drive',
      leading: RxNavTextButton(
        label: 'Cancel',
        onPressed: _busy ? null : () => context.pop(),
      ),
      trailing: RxNavTextButton(
        label: 'Create',
        bold: true,
        busy: _busy,
        onPressed: _title.text.trim().isEmpty ? null : _submit,
      ),
      child: Form(
        key: _formKey,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.only(top: RxSpace.m, bottom: RxSpace.xl),
          children: [
            RxFormSection(
              header: 'Details',
              children: [
                RxFormField(
                  controller: _title,
                  placeholder: 'Title (e.g. Sunday Coastal Run)',
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.next,
                  maxLength: 100,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Title is required'
                      : null,
                ),
                RxFormField(
                  controller: _description,
                  placeholder: 'Description (optional)',
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: 4,
                  maxLength: 1000,
                ),
              ],
            ),
            const SizedBox(height: RxSpace.m),
            RxSection(
              header: 'Visibility',
              footer: _visibility == 'public'
                  ? 'Anyone on RideX can discover this drive. Only people with the code can join.'
                  : 'Hidden from Discover. Only people you share the code with can find and join it.',
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    width: double.infinity,
                    child: CupertinoSlidingSegmentedControl<String>(
                      groupValue: _visibility,
                      children: const {
                        'public': Padding(
                          padding: EdgeInsets.symmetric(vertical: 6),
                          child: Text('Public'),
                        ),
                        'private': Padding(
                          padding: EdgeInsets.symmetric(vertical: 6),
                          child: Text('Private'),
                        ),
                      },
                      onValueChanged: (v) =>
                          setState(() => _visibility = v ?? 'public'),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: RxSpace.m),
            RxSection(
              header: 'When',
              footer: _schedule
                  ? null
                  : 'You can start the drive whenever everyone is ready.',
              children: [
                RxTile(
                  title: 'Schedule for later',
                  icon: CupertinoIcons.calendar,
                  iconColor: rx.warning,
                  trailing: CupertinoSwitch(
                    value: _schedule,
                    activeColor: rx.success,
                    onChanged: (v) {
                      setState(() => _schedule = v);
                      if (v && _scheduledAt == null) _pickDate();
                    },
                  ),
                ),
                if (_schedule)
                  RxTile(
                    title: 'Starts',
                    icon: CupertinoIcons.clock,
                    iconColor: rx.info,
                    detail: _scheduledAt == null
                        ? 'Choose'
                        : formatRideTime(_scheduledAt!),
                    onTap: _pickDate,
                  ),
              ],
            ),
            const SizedBox(height: RxSpace.m),
            RxSection(
              header: 'Route',
              footer:
                  'Optional. A destination lets everyone see how far they are from the finish.',
              children: [
                RxTile(
                  title: 'Meeting point',
                  icon: CupertinoIcons.location_fill,
                  iconColor: rx.success,
                  detail: _start == null ? 'Optional' : 'Set ✓',
                  onTap: () => _pickLocation(destination: false),
                ),
                RxTile(
                  title: 'Destination',
                  icon: CupertinoIcons.flag_fill,
                  iconColor: rx.accent,
                  detail: _destination == null ? 'Optional' : 'Set ✓',
                  onTap: () => _pickLocation(destination: true),
                ),
              ],
            ),
            const SizedBox(height: RxSpace.l),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: RxSpace.inset),
              child: RxButton(
                label: 'Create Drive',
                icon: CupertinoIcons.car_detailed,
                busy: _busy,
                onPressed: _title.text.trim().isEmpty ? null : _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-screen map with a fixed centre pin; "Done" returns the centre.
class MapPointPickerScreen extends StatefulWidget {
  const MapPointPickerScreen({super.key, required this.title, this.initial});

  final String title;
  final LatLng? initial;

  @override
  State<MapPointPickerScreen> createState() => _MapPointPickerScreenState();
}

class _MapPointPickerScreenState extends State<MapPointPickerScreen> {
  final _map = MapController();
  bool _locating = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    if (widget.initial == null) _useMyLocation(silent: true);
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  Future<void> _useMyLocation({bool silent = false}) async {
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (!silent && mounted) {
          showRxToast(context, 'Turn on Location to use your position.',
              isError: true);
        }
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied && !silent) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (!silent && mounted) {
          showRxToast(context, 'Location access is off for RideX.',
              isError: true);
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      if (!mounted) return;
      final target = LatLng(pos.latitude, pos.longitude);
      if (_ready) _map.move(target, 15);
    } catch (e) {
      if (!silent && mounted) showRxError(context, e);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    return RxPage(
      title: widget.title,
      leading: RxNavTextButton(
        label: 'Cancel',
        onPressed: () => Navigator.of(context).pop(),
      ),
      trailing: RxNavTextButton(
        label: 'Done',
        bold: true,
        onPressed: () => Navigator.of(context).pop(_map.camera.center),
      ),
      child: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: widget.initial ?? const LatLng(20.5937, 78.9629),
              initialZoom: widget.initial != null ? 15 : 4,
              onMapReady: () => _ready = true,
            ),
            children: const [
              RxTileLayer(),
              RxMapAttribution(),
            ],
          ),
          IgnorePointer(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 40),
                child: Icon(
                  CupertinoIcons.map_pin_ellipse,
                  size: 44,
                  color: rx.accent,
                  semanticLabel: 'Selected point',
                ),
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: MediaQuery.paddingOf(context).bottom + 24,
            child: _locating
                ? const SizedBox(
                    width: 44,
                    height: 44,
                    child: CupertinoActivityIndicator(),
                  )
                : RxMapButton(
                    icon: CupertinoIcons.location_fill,
                    semanticLabel: 'Use my location',
                    onPressed: () => _useMyLocation(),
                  ),
          ),
          Positioned(
            left: 16,
            right: 76,
            bottom: MediaQuery.paddingOf(context).bottom + 24,
            child: RxCard(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Text('Move the map to place the pin.',
                  style: rx.footnote),
            ),
          ),
        ],
      ),
    );
  }
}
