import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config.dart';
import '../../../core/providers.dart';
import '../../../data/api/friends_repository.dart';
import '../../../shared/ui/ui.dart';
import '../../auth/application/auth_notifier.dart';
import '../../permissions/presentation/permission_education_screen.dart';
import '../../ride/presentation/home_dashboard_screen.dart';

final myStatsProvider = FutureProvider.autoDispose<UserStatsDto>(
  (ref) => ref.watch(friendsRepositoryProvider).myStats(),
);

/// Profile tab: identity, stats, garage, settings and account actions.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _changePhoto(BuildContext context, WidgetRef ref) async {
    final source = await showRxActionSheet<ImageSource>(
      context,
      title: 'Profile Photo',
      actions: const [
        RxSheetAction(label: 'Take Photo', value: ImageSource.camera),
        RxSheetAction(label: 'Choose from Library', value: ImageSource.gallery),
      ],
    );
    if (source == null) return;
    final file = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (file == null) return;
    try {
      await ref.read(authNotifierProvider.notifier).uploadAvatar(File(file.path));
      ref.invalidate(mediaTokenProvider);
      if (context.mounted) showRxToast(context, 'Photo updated');
    } catch (e) {
      if (context.mounted) showRxError(context, e);
    }
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final choice = await showRxActionSheet<bool>(
      context,
      message: 'Live sharing and group-drive tracking will stop on this phone.',
      actions: const [
        RxSheetAction(label: 'Sign Out', value: true, destructive: true),
      ],
    );
    if (choice == true) {
      await ref.read(authNotifierProvider.notifier).logout();
    }
  }

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final ok = await confirmRx(
      context,
      title: 'Delete Account?',
      message:
          'Your profile, posts, friends and shared locations will be permanently deleted. Drives saved on this phone stay here. This can\'t be undone.',
      confirmLabel: 'Delete Account',
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(authNotifierProvider.notifier).deleteAccount();
    } catch (e) {
      if (context.mounted) showRxError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rx = context.rx;
    final user = ref.watch(authNotifierProvider).user;
    final stats = ref.watch(myStatsProvider).valueOrNull;
    final local = ref.watch(driveStatsProvider).valueOrNull;
    final permission = ref.watch(locationPermissionProvider).valueOrNull;

    return RxLargeTitlePage(
      title: 'Profile',
      onRefresh: () async {
        ref.invalidate(myStatsProvider);
        await ref.read(authNotifierProvider.notifier).refreshProfile();
      },
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: RxSpace.s),
            child: RxSection(
              children: [
                RxPressable(
                  onTap: () => context.push('/profile/edit'),
                  child: Container(
                    color: rx.card,
                    padding: const EdgeInsets.all(RxSpace.m),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => _changePhoto(context, ref),
                          child: Stack(
                            children: [
                              RxAvatar(
                                name: user?.displayName ?? '?',
                                avatarPath: user?.avatarPath,
                                size: 64,
                              ),
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: rx.accent,
                                    shape: BoxShape.circle,
                                    border:
                                        Border.all(color: rx.card, width: 2),
                                  ),
                                  child: const Icon(CupertinoIcons.camera_fill,
                                      size: 12, color: Color(0xFFFFFFFF)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: RxSpace.m),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(user?.displayName ?? '',
                                  style: rx.title3,
                                  overflow: TextOverflow.ellipsis),
                              Text('@${user?.username ?? ''}',
                                  style: rx.subheadline),
                              if ((user?.bio ?? '').isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(user!.bio!,
                                    style: rx.footnote, maxLines: 2),
                              ],
                            ],
                          ),
                        ),
                        Icon(CupertinoIcons.chevron_right,
                            size: 16, color: rx.tertiaryLabel),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        RxSliverPadding(
          bottom: RxSpace.m,
          child: Row(
            children: [
              _StatCell(value: '${local?.count ?? 0}', label: 'Drives'),
              _StatCell(
                  value: (local?.totalKm ?? 0).toStringAsFixed(0),
                  label: 'km'),
              _StatCell(value: '${stats?.friends ?? 0}', label: 'Friends'),
              _StatCell(
                  value:
                      '${(stats?.ridesHosted ?? 0) + (stats?.ridesJoined ?? 0)}',
                  label: 'Group'),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: RxSection(
            header: 'My Stuff',
            children: [
              RxTile(
                title: 'Garage',
                icon: CupertinoIcons.car_detailed,
                iconColor: rx.accent,
                onTap: () => context.push('/profile/garage'),
              ),
              RxTile(
                title: 'Drive History',
                icon: CupertinoIcons.clock_fill,
                iconColor: rx.indigo,
                detail: '${local?.count ?? 0}',
                onTap: () => context.go('/drive/history'),
              ),
              RxTile(
                title: 'Location Sharing',
                icon: CupertinoIcons.location_fill,
                iconColor: rx.info,
                onTap: () => context.go('/friends/sharing'),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: RxSection(
            header: 'Privacy',
            footer:
                'RideX only uses location while you record a drive, join a live group drive or share with friends.',
            children: [
              RxTile(
                title: 'Location Access',
                icon: CupertinoIcons.location_circle_fill,
                iconColor: rx.success,
                detail: permission == null
                    ? ''
                    : permissionGranted(permission)
                        ? 'Allowed'
                        : 'Off',
                onTap: () => context.push('/permissions'),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: RxSection(
            header: 'About',
            children: [
              RxTile(
                title: 'Server Status',
                icon: CupertinoIcons.antenna_radiowaves_left_right,
                iconColor: rx.gray,
                onTap: () => launchUrl(
                  Uri.parse('${ApiConfig.apiBaseUrl}/health'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
              RxTile(
                title: 'Version',
                icon: CupertinoIcons.info_circle_fill,
                iconColor: rx.gray,
                detail: '1.2.0',
                chevron: false,
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: RxSection(
            children: [
              RxTile(
                title: 'Sign Out',
                destructive: true,
                chevron: false,
                onTap: () => _signOut(context, ref),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: RxSection(
            children: [
              RxTile(
                title: 'Delete Account',
                destructive: true,
                chevron: false,
                onTap: () => _deleteAccount(context, ref),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final rx = context.rx;
    return Expanded(
      child: Semantics(
        label: '$value $label',
        excludeSemantics: true,
        child: Column(
          children: [
            Text(value, style: rx.numeric(20)),
            Text(label, style: rx.caption),
          ],
        ),
      ),
    );
  }
}
