import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/api/api_client.dart';
import '../../../shared/widgets/glass.dart';
import 'discover_rides_screen.dart';

class CreateRideScreen extends ConsumerStatefulWidget {
  const CreateRideScreen({super.key});

  @override
  ConsumerState<CreateRideScreen> createState() => _CreateRideScreenState();
}

class _CreateRideScreenState extends ConsumerState<CreateRideScreen> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  String _visibility = 'public';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Title is required');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ride = await ref.read(ridesRepositoryProvider).createRide(
            title: _title.text.trim(),
            description: _description.text.trim().isEmpty
                ? null
                : _description.text.trim(),
            visibility: _visibility,
          );
      ref.invalidate(discoverRidesProvider);
      if (mounted) context.go('/rides/live/${ride.id}');
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      appBar: const GlassAppBar(title: 'Create drive'),
      padding: const EdgeInsets.all(24),
      body: SingleChildScrollView(
        child: Column(
          children: [
            GlassFormPanel(
              children: [
                GlassFormField(controller: _title, label: 'Title'),
                GlassFormField(
                  controller: _description,
                  label: 'Description (optional)',
                  maxLines: 3,
                ),
                DropdownButtonFormField<String>(
                  value: _visibility,
                  dropdownColor: AppTheme.surface,
                  decoration: const InputDecoration(
                    labelText: 'Visibility',
                    labelStyle: TextStyle(color: AppTheme.textSecondary),
                    border: InputBorder.none,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'public', child: Text('Public')),
                    DropdownMenuItem(value: 'private', child: Text('Private')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _visibility = v);
                  },
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: AppTheme.accent)),
            ],
            const SizedBox(height: 32),
            GlassButton(
              label: 'CREATE',
              busy: _busy,
              onPressed: _busy ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}
