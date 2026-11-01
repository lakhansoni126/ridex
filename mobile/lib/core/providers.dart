import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api/api_client.dart';
import '../data/api/auth_repository.dart';
import '../data/api/friends_repository.dart';
import '../data/api/posts_repository.dart';
import '../data/api/rides_repository.dart';
import '../data/api/shares_repository.dart';
import '../data/local/location_buffer.dart';
import '../data/local/token_store.dart';
import '../services/background_location_service.dart';

final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());

final apiClientProvider = Provider<ApiClient>((ref) {
  final store = ref.watch(tokenStoreProvider);
  return ApiClient(
    readAccessToken: store.readAccessToken,
    readRefreshToken: store.readRefreshToken,
    writeTokens: store.writeTokens,
    clearTokens: store.clear,
  );
});

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(apiClientProvider)),
);

final ridesRepositoryProvider = Provider<RidesRepository>(
  (ref) => RidesRepository(ref.watch(apiClientProvider)),
);

final friendsRepositoryProvider = Provider<FriendsRepository>(
  (ref) => FriendsRepository(ref.watch(apiClientProvider)),
);

final sharesRepositoryProvider = Provider<SharesRepository>(
  (ref) => SharesRepository(ref.watch(apiClientProvider)),
);

final postsRepositoryProvider = Provider<PostsRepository>(
  (ref) => PostsRepository(ref.watch(apiClientProvider)),
);

final locationBufferProvider = Provider<LocationBuffer>(
  (ref) => LocationBuffer(),
);

final backgroundLocationServiceProvider =
    Provider<BackgroundLocationService>((ref) {
  return BackgroundLocationService(
    buffer: ref.watch(locationBufferProvider),
    ridesRepository: ref.watch(ridesRepositoryProvider),
    sharesRepository: ref.watch(sharesRepositoryProvider),
    tokenStore: ref.watch(tokenStoreProvider),
  );
});
