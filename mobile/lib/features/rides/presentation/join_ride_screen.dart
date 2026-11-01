import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/api/api_client.dart';
import '../../../shared/widgets/glass_container.dart';
import 'discover_rides_screen.dart';

class JoinRideScreen extends ConsumerStatefulWidget {
  const JoinRideScreen({super.key});

  @override
  ConsumerState<JoinRideScreen> createState() => _JoinRideScreenState();
}

class _JoinRideScreenState extends ConsumerState<JoinRideScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _code.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _error = 'Enter a join code');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ride =
          await ref.read(ridesRepositoryProvider).joinRide(joinCode: code);
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
        title: const Text('Join with code'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            GlassContainer(
              child: TextField(
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(
                  color: Colors.white,
                  letterSpacing: 4,
                  fontSize: 22,
                ),
                decoration: const InputDecoration(
                  labelText: 'Join code',
                  labelStyle: TextStyle(color: AppTheme.textSecondary),
                  border: InputBorder.none,
                ),
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
                    : const Text('JOIN DRIVE'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
