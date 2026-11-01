import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/api/api_client.dart';
import '../../../shared/widgets/glass_container.dart';
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
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Create drive'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              GlassContainer(
                child: Column(
                  children: [
                    TextField(
                      controller: _title,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Title',
                        labelStyle: TextStyle(color: AppTheme.textSecondary),
                        border: InputBorder.none,
                      ),
                    ),
                    const Divider(color: Colors.white12),
                    TextField(
                      controller: _description,
                      maxLines: 3,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Description (optional)',
                        labelStyle: TextStyle(color: AppTheme.textSecondary),
                        border: InputBorder.none,
                      ),
                    ),
                    const Divider(color: Colors.white12),
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
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: const TextStyle(color: AppTheme.accent)),
              ],
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('CREATE'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
