import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/api/api_client.dart';
import '../../../data/api/friends_repository.dart';
import '../../../shared/widgets/glass.dart';

final friendsListProvider =
    FutureProvider.autoDispose<List<PublicUserDto>>((ref) {
  return ref.watch(friendsRepositoryProvider).listFriends();
});

final friendRequestsProvider =
    FutureProvider.autoDispose<FriendRequestsDto>((ref) {
  return ref.watch(friendsRepositoryProvider).listRequests();
});

class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  final _username = TextEditingController();
  bool _sending = false;
  String? _message;

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  Future<void> _sendRequest() async {
    final name = _username.text.trim();
    if (name.length < 3) {
      setState(() => _message = 'Enter a username');
      return;
    }
    setState(() {
      _sending = true;
      _message = null;
    });
    try {
      await ref.read(friendsRepositoryProvider).sendRequest(name);
      _username.clear();
      ref.invalidate(friendRequestsProvider);
      setState(() => _message = 'Request sent');
    } on ApiException catch (e) {
      setState(() => _message = e.message);
    } catch (e) {
      setState(() => _message = e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final friendsAsync = ref.watch(friendsListProvider);
    final requestsAsync = ref.watch(friendRequestsProvider);
    final theme = Theme.of(context);

    return GlassScaffold(
      appBar: const GlassAppBar(title: 'Friends'),
      body: RefreshIndicator(
        color: AppTheme.accent,
        onRefresh: () async {
          ref.invalidate(friendsListProvider);
          ref.invalidate(friendRequestsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            GlassContainer(
              variant: GlassVariant.intense,
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _username,
                      style: const TextStyle(color: AppTheme.textPrimary),
                      cursorColor: AppTheme.accent,
                      decoration: const InputDecoration(
                        hintText: 'Add by username',
                        hintStyle: TextStyle(color: AppTheme.textSecondary),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: _sending ? null : _sendRequest,
                    child: const Text('ADD'),
                  ),
                ],
              ),
            ),
            if (_message != null) ...[
              const SizedBox(height: 8),
              Text(_message!, style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: 24),
            Text('Requests', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            requestsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('$e'),
              data: (req) {
                if (req.incoming.isEmpty && req.outgoing.isEmpty) {
                  return Text('No pending requests',
                      style: theme.textTheme.bodyMedium);
                }
                return Column(
                  children: [
                    ...req.incoming.map((f) => _requestTile(
                          title: f.requester?.displayName ??
                              f.requester?.username ??
                              'Driver',
                          subtitle: 'wants to connect',
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.check, color: Colors.green),
                                onPressed: () async {
                                  await ref
                                      .read(friendsRepositoryProvider)
                                      .acceptRequest(f.id);
                                  ref.invalidate(friendsListProvider);
                                  ref.invalidate(friendRequestsProvider);
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, color: AppTheme.accent),
                                onPressed: () async {
                                  await ref
                                      .read(friendsRepositoryProvider)
                                      .declineRequest(f.id);
                                  ref.invalidate(friendRequestsProvider);
                                },
                              ),
                            ],
                          ),
                        )),
                    ...req.outgoing.map((f) => _requestTile(
                          title: f.addressee?.displayName ??
                              f.addressee?.username ??
                              'Driver',
                          subtitle: 'outgoing',
                          trailing: const Text('Pending',
                              style: TextStyle(color: AppTheme.textSecondary)),
                        )),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            Text('Your friends', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            friendsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('$e'),
              data: (friends) {
                if (friends.isEmpty) {
                  return Text('No friends yet — add drivers by username.',
                      style: theme.textTheme.bodyMedium);
                }
                return Column(
                  children: friends
                      .map(
                        (f) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: GlassContainer(
                            variant: GlassVariant.card,
                            padding: const EdgeInsets.all(16),
                            borderRadius: 16,
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: AppTheme.surface,
                                  child: Text(f.displayName.isNotEmpty
                                      ? f.displayName[0].toUpperCase()
                                      : '?'),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(f.displayName,
                                          style: const TextStyle(
                                              color: AppTheme.textPrimary)),
                                      Text('@${f.username}',
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(fontSize: 13)),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.person_remove_outlined,
                                      color: AppTheme.textSecondary),
                                  onPressed: () async {
                                    await ref
                                        .read(friendsRepositoryProvider)
                                        .unfriend(f.id);
                                    ref.invalidate(friendsListProvider);
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _requestTile({
    required String title,
    required String subtitle,
    required Widget trailing,
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
                ],
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}
