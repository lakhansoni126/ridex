import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/api/api_client.dart';
import '../../../data/api/shares_repository.dart';
import '../../../data/ws/ws_client.dart';
import '../../../shared/widgets/glass.dart';
import '../../friends/presentation/friends_screen.dart';

final locationSharesProvider =
    FutureProvider.autoDispose<LocationSharesListDto>((ref) {
  return ref.watch(sharesRepositoryProvider).listShares();
});

class LocationSharingScreen extends ConsumerStatefulWidget {
  const LocationSharingScreen({super.key});

  @override
  ConsumerState<LocationSharingScreen> createState() =>
      _LocationSharingScreenState();
}

class _LocationSharingScreenState extends ConsumerState<LocationSharingScreen> {
  String _duration = '1h';
  final Set<String> _selectedFriends = {};
  bool _busy = false;
  String? _error;
  LocationShareWsSession? _ws;

  @override
  void dispose() {
    _ws?.disconnect();
    super.dispose();
  }

  Future<void> _startShare() async {
    if (_selectedFriends.isEmpty) {
      setState(() => _error = 'Select at least one friend');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final share = await ref.read(sharesRepositoryProvider).createShare(
            duration: _duration,
            friendIds: _selectedFriends.toList(),
          );
      final token = await ref.read(tokenStoreProvider).readAccessToken();
      if (token != null) {
        final ws = LocationShareWsSession(accessToken: token);
        _ws = ws;
        await ws.connect(onMessage: (_) {});
        await ref.read(backgroundLocationServiceProvider).startForShare(
              shareId: share.id,
              ws: ws,
            );
      }
      ref.invalidate(locationSharesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location sharing started')),
        );
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stopShare(String shareId) async {
    await ref.read(sharesRepositoryProvider).stopShare(shareId);
    await ref.read(backgroundLocationServiceProvider).stopShare();
    await _ws?.disconnect();
    _ws = null;
    ref.invalidate(locationSharesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final sharesAsync = ref.watch(locationSharesProvider);
    final friendsAsync = ref.watch(friendsListProvider);
    final theme = Theme.of(context);

    return GlassScaffold(
      appBar: const GlassAppBar(title: 'Location sharing'),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Share with friends', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          GlassContainer(
            variant: GlassVariant.intense,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Duration',
                    style: TextStyle(color: AppTheme.textSecondary)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final d in const ['1h', '8h', 'indefinite'])
                      ChoiceChip(
                        label: Text(d == 'indefinite' ? 'Until I stop' : d),
                        selected: _duration == d,
                        onSelected: (_) => setState(() => _duration = d),
                        selectedColor: AppTheme.accent,
                        backgroundColor: AppTheme.surface,
                        labelStyle: TextStyle(
                          color: _duration == d ? Colors.white : Colors.white70,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('Friends',
                    style: TextStyle(color: AppTheme.textSecondary)),
                const SizedBox(height: 8),
                friendsAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text('$e'),
                  data: (friends) {
                    if (friends.isEmpty) {
                      return Text(
                        'Add friends first to share your location.',
                        style: theme.textTheme.bodyMedium,
                      );
                    }
                    return Column(
                      children: friends.map((f) {
                        final selected = _selectedFriends.contains(f.id);
                        return CheckboxListTile(
                          value: selected,
                          activeColor: AppTheme.accent,
                          title: Text(f.displayName,
                              style: const TextStyle(
                                  color: AppTheme.textPrimary)),
                          subtitle: Text('@${f.username}',
                              style: theme.textTheme.bodyMedium),
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                _selectedFriends.add(f.id);
                              } else {
                                _selectedFriends.remove(f.id);
                              }
                            });
                          },
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: AppTheme.accent)),
          ],
          const SizedBox(height: 16),
          GlassButton(
            label: 'START SHARING',
            busy: _busy,
            onPressed: _busy ? null : _startShare,
          ),
          const SizedBox(height: 32),
          Text('Active & recent', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          sharesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('$e'),
            data: (list) {
              final mine = list.mine;
              final incoming = list.sharedWithMe;
              if (mine.isEmpty && incoming.isEmpty) {
                return Text('No shares yet', style: theme.textTheme.bodyMedium);
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...mine.map((s) => _shareCard(
                        title: 'You → ${s.grants.map((g) => g.friend?.displayName ?? 'friend').join(', ')}',
                        subtitle:
                            '${s.duration} · ${s.isActive ? 'active' : 'stopped'}',
                        trailing: s.isActive
                            ? TextButton(
                                onPressed: () => _stopShare(s.id),
                                child: const Text('STOP',
                                    style: TextStyle(color: AppTheme.accent)),
                              )
                            : null,
                        onRevoke: s.isActive && s.grants.isNotEmpty
                            ? () async {
                                final g = s.grants.first;
                                await ref
                                    .read(sharesRepositoryProvider)
                                    .revokeGrant(s.id, g.friendUserId);
                                ref.invalidate(locationSharesProvider);
                              }
                            : null,
                      )),
                  if (incoming.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text('Shared with you', style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 8),
                    ...incoming.map((s) => _shareCard(
                          title: s.owner?.displayName ?? 'Friend',
                          subtitle: s.isActive ? 'Live now' : 'Ended',
                        )),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _shareCard({
    required String title,
    required String subtitle,
    Widget? trailing,
    VoidCallback? onRevoke,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassContainer(
        variant: GlassVariant.card,
        padding: const EdgeInsets.all(16),
        borderRadius: 16,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(color: AppTheme.textPrimary)),
                  Text(subtitle,
                      style: const TextStyle(
                          color: AppTheme.textSecondary, fontSize: 13)),
                  if (onRevoke != null)
                    TextButton(
                      onPressed: onRevoke,
                      child: const Text('Revoke first grant',
                          style: TextStyle(fontSize: 12)),
                    ),
                ],
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }
}
