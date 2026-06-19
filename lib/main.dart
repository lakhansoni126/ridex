import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/theme/app_theme.dart';
import 'features/ride/presentation/home_dashboard_screen.dart';
import 'features/ride/presentation/ride_dashboard_screen.dart';
import 'features/history/presentation/history_screen.dart';
import 'features/map/presentation/map_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize Isar here if needed
  runApp(const ProviderScope(child: RideAnalyticsApp()));
}

final goRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
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
        path: '/map',
        builder: (context, state) => const MapScreen(),
      ),
    ],
  );
});

class RideAnalyticsApp extends ConsumerWidget {
  const RideAnalyticsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);

    return MaterialApp.router(
      title: 'Ride Analytics',
      theme: AppTheme.darkTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark, // Enforce dark theme
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
