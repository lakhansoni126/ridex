import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/api/posts_repository.dart';
import '../features/auth/application/auth_notifier.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/auth/presentation/splash_screen.dart';
import '../features/community/presentation/community_feed_screen.dart';
import '../features/community/presentation/compose_post_screen.dart';
import '../features/community/presentation/post_detail_screen.dart';
import '../features/friends/presentation/add_friend_screen.dart';
import '../features/friends/presentation/friends_screen.dart';
import '../features/garage/presentation/garage_screen.dart';
import '../features/history/presentation/history_screen.dart';
import '../features/history/presentation/ride_detail_screen.dart';
import '../features/map/presentation/map_screen.dart';
import '../features/permissions/presentation/permission_education_screen.dart';
import '../features/profile/presentation/edit_profile_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/ride/presentation/home_dashboard_screen.dart';
import '../features/ride/presentation/ride_dashboard_screen.dart';
import '../features/ride/presentation/ride_replay_screen.dart';
import '../features/rides/presentation/create_ride_screen.dart';
import '../features/rides/presentation/join_ride_screen.dart';
import '../features/rides/presentation/live_ride_map_screen.dart';
import '../features/rides/presentation/rides_screen.dart';
import '../features/sharing/presentation/friends_map_screen.dart';
import '../features/sharing/presentation/location_sharing_screen.dart';
import '../features/shell/app_shell.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Full-screen iOS modal (slides up, no tab bar).
Page<void> _modal(GoRouterState state, Widget child) => CupertinoPage<void>(
      key: state.pageKey,
      fullscreenDialog: true,
      child: child,
    );

final goRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final status = ref.read(authNotifierProvider).status;
      final loc = state.matchedLocation;
      final isAuthRoute = loc == '/login' || loc == '/register';

      if (status == AuthStatus.unknown) {
        return loc == '/splash' ? null : '/splash';
      }
      if (status == AuthStatus.unauthenticated) {
        return isAuthRoute ? null : '/login';
      }
      if (isAuthRoute || loc == '/splash') return '/drive';
      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (_, __) => '/drive'),
      GoRoute(
        path: '/splash',
        pageBuilder: (c, s) =>
            NoTransitionPage(key: s.pageKey, child: const SplashScreen()),
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (c, s) =>
            NoTransitionPage(key: s.pageKey, child: const LoginScreen()),
      ),
      GoRoute(
        path: '/register',
        builder: (c, s) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/permissions',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (c, s) =>
            _modal(s, const PermissionEducationScreen()),
      ),

      // ── Full-screen experiences above the tab bar ──
      GoRoute(
        path: '/record',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (c, s) => _modal(s, const RideDashboardScreen()),
      ),
      GoRoute(
        path: '/map',
        parentNavigatorKey: rootNavigatorKey,
        builder: (c, s) => const MapScreen(),
      ),
      GoRoute(
        path: '/drive/ride/:id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (c, s) => RideDetailScreen(
          rideId: int.tryParse(s.pathParameters['id'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: '/drive/ride/:id/replay',
        parentNavigatorKey: rootNavigatorKey,
        builder: (c, s) => RideReplayScreen(
          rideId: int.tryParse(s.pathParameters['id'] ?? '') ?? 0,
        ),
      ),
      GoRoute(
        path: '/rides/live/:id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (c, s) =>
            LiveRideMapScreen(rideId: s.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: '/friends/map',
        parentNavigatorKey: rootNavigatorKey,
        builder: (c, s) => const FriendsMapScreen(),
      ),
      GoRoute(
        path: '/feed/compose',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (c, s) => _modal(s, const ComposePostScreen()),
      ),
      GoRoute(
        path: '/rides/create',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (c, s) => _modal(s, const CreateRideScreen()),
      ),
      GoRoute(
        path: '/rides/join',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (c, s) => _modal(
          s,
          JoinRideScreen(initialCode: s.uri.queryParameters['code']),
        ),
      ),

      // ── Tabs ──
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/drive',
              builder: (c, s) => const HomeDashboardScreen(),
              routes: [
                GoRoute(
                  path: 'history',
                  builder: (c, s) => const HistoryScreen(),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/rides',
              builder: (c, s) => const RidesScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/feed',
              builder: (c, s) => const CommunityFeedScreen(),
              routes: [
                GoRoute(
                  path: 'post/:id',
                  builder: (c, s) => PostDetailScreen(
                    postId: s.pathParameters['id'] ?? '',
                    initialPost: s.extra is PostDto ? s.extra as PostDto : null,
                  ),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/friends',
              builder: (c, s) => const FriendsScreen(),
              routes: [
                GoRoute(
                  path: 'add',
                  builder: (c, s) => const AddFriendScreen(),
                ),
                GoRoute(
                  path: 'sharing',
                  builder: (c, s) => const LocationSharingScreen(),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/profile',
              builder: (c, s) => const ProfileScreen(),
              routes: [
                GoRoute(
                  path: 'edit',
                  builder: (c, s) => const EditProfileScreen(),
                ),
                GoRoute(
                  path: 'garage',
                  builder: (c, s) => const GarageScreen(),
                ),
              ],
            ),
          ]),
        ],
      ),
    ],
  );
});

/// Bridges Riverpod auth changes into GoRouter refresh.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Ref ref) {
    ref.listen<AuthStatus>(
      authNotifierProvider.select((s) => s.status),
      (_, __) => notifyListeners(),
    );
  }
}
