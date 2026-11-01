import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/app_theme.dart';
import 'database/database_service.dart';
import 'features/auth/application/auth_notifier.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/auth/presentation/register_screen.dart';
import 'features/community/presentation/community_feed_screen.dart';
import 'features/community/presentation/compose_post_screen.dart';
import 'features/friends/presentation/friends_screen.dart';
import 'features/garage/presentation/garage_screen.dart';
import 'features/history/presentation/history_screen.dart';
import 'features/history/presentation/ride_detail_screen.dart';
import 'features/map/presentation/map_screen.dart';
import 'features/permissions/presentation/permission_education_screen.dart';
import 'features/ride/presentation/home_dashboard_screen.dart';
import 'features/ride/presentation/ride_dashboard_screen.dart';
import 'features/ride/presentation/ride_replay_screen.dart';
import 'features/rides/presentation/create_ride_screen.dart';
import 'features/rides/presentation/discover_rides_screen.dart';
import 'features/rides/presentation/join_ride_screen.dart';
import 'features/rides/presentation/live_ride_map_screen.dart';
import 'features/sharing/presentation/location_sharing_screen.dart';

// Global instance for now, can be moved to Riverpod later
final dbService = DatabaseService();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dbService.init();
  } catch (e) {
    debugPrint('Database initialization failed: $e');
  }

  runApp(const ProviderScope(child: RideAnalyticsApp()));
}

final goRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final status = ref.read(authNotifierProvider).status;
      final loc = state.matchedLocation;
      final isAuthRoute = loc == '/login' || loc == '/register';

      if (status == AuthStatus.unknown) return null;

      if (status == AuthStatus.unauthenticated) {
        if (isAuthRoute) return null;
        return '/login';
      }

      // Authenticated
      if (isAuthRoute) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/permissions',
        builder: (context, state) => const PermissionEducationScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => const HomeDashboardScreen(),
      ),
      GoRoute(
        path: '/ride',
        builder: (context, state) => const RideDashboardScreen(),
      ),
      GoRoute(
        path: '/history',
        builder: (context, state) => const HistoryScreen(),
      ),
      GoRoute(
        path: '/ride-detail/:id',
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
          return RideDetailScreen(rideId: id);
        },
      ),
      GoRoute(
        path: '/map',
        builder: (context, state) => const MapScreen(),
      ),
      GoRoute(
        path: '/replay',
        builder: (context, state) => const RideReplayScreen(),
      ),
      GoRoute(
        path: '/garage',
        builder: (context, state) => const GarageScreen(),
      ),
      GoRoute(
        path: '/rides',
        builder: (context, state) => const DiscoverRidesScreen(),
      ),
      GoRoute(
        path: '/rides/create',
        builder: (context, state) => const CreateRideScreen(),
      ),
      GoRoute(
        path: '/rides/join',
        builder: (context, state) => const JoinRideScreen(),
      ),
      GoRoute(
        path: '/rides/live/:id',
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return LiveRideMapScreen(rideId: id);
        },
      ),
      GoRoute(
        path: '/friends',
        builder: (context, state) => const FriendsScreen(),
      ),
      GoRoute(
        path: '/sharing',
        builder: (context, state) => const LocationSharingScreen(),
      ),
      GoRoute(
        path: '/community',
        builder: (context, state) => const CommunityFeedScreen(),
      ),
      GoRoute(
        path: '/community/compose',
        builder: (context, state) => const ComposePostScreen(),
      ),
    ],
  );
});

/// Bridges Riverpod auth changes into GoRouter refresh.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(this._ref) {
    _ref.listen<AuthState>(authNotifierProvider, (_, __) => notifyListeners());
  }

  final Ref _ref;
}

class RideAnalyticsApp extends ConsumerWidget {
  const RideAnalyticsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);

    return MaterialApp.router(
      title: 'RideX',
      theme: AppTheme.darkTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
