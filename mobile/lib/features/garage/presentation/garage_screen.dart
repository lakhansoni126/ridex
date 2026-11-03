import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../database/models.dart';
import '../../../main.dart';
import '../../../shared/ui/ui.dart';

final garageProvider =
    FutureProvider.autoDispose<List<Vehicle>>((ref) => dbService.getVehicles());

/// The user's cars, stored on the device.
class GarageScreen extends ConsumerWidget {
  const GarageScreen({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, [Vehicle? v]) async {
    final saved = await Navigator.of(context, rootNavigator: true).push<bool>(
      CupertinoPageRoute(
        fullscreenDialog: true,
        builder: (_) => _VehicleForm(vehicle: v),
      ),
    );
    if (saved == true) ref.invalidate(garageProvider);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Vehicle v) async {
    final ok = await confirmRx(
      context,
      title: 'Remove ${v.name}?',
      confirmLabel: 'Remove',
    );
    if (!ok) return;
    await dbService.deleteVehicle(v.id);
    ref.invalidate(garageProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rx = context.rx;
    final cars = ref.watch(garageProvider);
    return RxLargeTitlePage(
      title: 'Garage',
      previousPageTitle: 'Profile',
      trailing: RxNavIconButton(
        icon: CupertinoIcons.add,
        semanticLabel: 'Add car',
        onPressed: () => _edit(context, ref),
      ),
      slivers: [
        ...cars.when(
          loading: () => const [RxSliverLoading()],
          error: (e, _) => [RxSliverCenter(child: RxErrorState(error: e))],
          data: (list) => list.isEmpty
              ? [
                  RxSliverCenter(
                    child: RxEmptyState(
                      icon: CupertinoIcons.car_detailed,
                      title: 'Your Garage Is Empty',
                      message: 'Add the cars you drive.',
                      actionLabel: 'Add a Car',
                      onAction: () => _edit(context, ref),
                    ),
                  ),
                ]
              : [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: RxSpace.s),
                      child: RxSection(
                        footer: 'Swipe left on a car to remove it.',
                        children: [
                          for (final v in list)
                            Dismissible(
                              key: ValueKey(v.id),
                              direction: DismissDirection.endToStart,
                              confirmDismiss: (_) async {
                                await _delete(context, ref, v);
                                return false;
                              },
                              background: Container(
                                color: rx.destructive,
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                child: const Icon(CupertinoIcons.trash,
                                    color: Color(0xFFFFFFFF)),
                              ),
                              child: RxTile(
                                title: v.name,
                                subtitle: [
                                  v.brand,
                                  if ((v.model ?? '').isNotEmpty) v.model!,
                                  if (v.year != null) '${v.year}',
                                ].where((s) => s.isNotEmpty).join(' · '),
                                icon: CupertinoIcons.car_detailed,
                                iconColor: rx.accent,
                                onTap: () => _edit(context, ref, v),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
        ),
      ],
    );
  }
}

class _VehicleForm extends StatefulWidget {
  const _VehicleForm({this.vehicle});

  final Vehicle? vehicle;

  @override
  State<_VehicleForm> createState() => _VehicleFormState();
}

class _VehicleFormState extends State<_VehicleForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.vehicle?.name ?? '');
  late final _brand = TextEditingController(text: widget.vehicle?.brand ?? '');
  late final _model = TextEditingController(text: widget.vehicle?.model ?? '');
  late final _year =
      TextEditingController(text: widget.vehicle?.year?.toString() ?? '');

  @override
  void dispose() {
    _name.dispose();
    _brand.dispose();
    _model.dispose();
    _year.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final v = widget.vehicle ?? Vehicle();
    v
      ..name = _name.text.trim()
      ..brand = _brand.text.trim()
      ..model = _model.text.trim().isEmpty ? null : _model.text.trim()
      ..year = int.tryParse(_year.text.trim());
    try {
      await dbService.saveVehicle(v);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showRxError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxYear = DateTime.now().year + 1;
    return RxPage(
      title: widget.vehicle == null ? 'Add Car' : 'Edit Car',
      leading: RxNavTextButton(
        label: 'Cancel',
        onPressed: () => Navigator.of(context).pop(false),
      ),
      trailing: RxNavTextButton(label: 'Save', bold: true, onPressed: _save),
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: RxSpace.l),
          children: [
            RxFormSection(
              children: [
                RxFormField(
                  controller: _name,
                  prefix: 'Nickname',
                  placeholder: 'Daily Driver',
                  textCapitalization: TextCapitalization.words,
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Give it a name' : null,
                ),
                RxFormField(
                  controller: _brand,
                  prefix: 'Make',
                  placeholder: 'Toyota',
                  textCapitalization: TextCapitalization.words,
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Enter the make' : null,
                ),
                RxFormField(
                  controller: _model,
                  prefix: 'Model',
                  placeholder: 'Supra (optional)',
                  textCapitalization: TextCapitalization.words,
                ),
                RxFormField(
                  controller: _year,
                  prefix: 'Year',
                  placeholder: 'Optional',
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.isEmpty) return null;
                    final y = int.tryParse(t);
                    if (y == null || y < 1900 || y > maxYear) {
                      return 'Enter a year between 1900 and $maxYear';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
