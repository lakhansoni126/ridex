import 'package:flutter_test/flutter_test.dart';
import 'package:ridex/core/errors.dart';
import 'package:ridex/data/api/api_client.dart';
import 'package:ridex/data/api/friends_repository.dart';
import 'package:ridex/data/api/posts_repository.dart';
import 'package:ridex/data/api/rides_repository.dart';
import 'package:ridex/data/api/shares_repository.dart';
import 'package:ridex/features/auth/presentation/auth_validators.dart';
import 'package:ridex/shared/ui/rx_stats.dart';

const _user = {
  'id': 'u1',
  'username': 'alex',
  'display_name': 'Alex Driver',
  'avatar_path': null,
};

void main() {
  group('validators', () {
    test('email', () {
      expect(validateEmail('alex@ridex.local'), isNull);
      expect(validateEmail('nope'), isNotNull);
      expect(validateEmail(''), isNotNull);
    });
    test('username mirrors server rule', () {
      expect(validateUsername('alex_92.k'), isNull);
      expect(validateUsername('Alex'), isNull); // lower-cased before check
      expect(validateUsername('ab'), isNotNull);
      expect(validateUsername('has space'), isNotNull);
    });
    test('password length', () {
      expect(validatePassword('1234567'), isNotNull);
      expect(validatePassword('12345678'), isNull);
    });
  });

  group('API contract parsing', () {
    test('ride hides codes for non-participants', () {
      final ride = RideDto.fromJson({
        'id': 'r1',
        'host_id': 'u1',
        'host': _user,
        'title': 'Sunday run',
        'visibility': 'public',
        'status': 'live',
        'join_code': null,
        'invite_token': null,
        'participant_count': 3,
        'is_participant': false,
        'participants': [],
      });
      expect(ride.joinCode, isNull);
      expect(ride.isLive, isTrue);
      expect(ride.participantCount, 3);
      expect(ride.host?.displayName, 'Alex Driver');
    });

    test('participant status-only update keeps position', () {
      final p = ParticipantDto.fromJson({
        'user_id': 'u2',
        'status': 'riding',
        'lat': 12.9,
        'lon': 77.6,
        'user': _user,
      });
      final updated = p.copyWith(status: 'paused');
      expect(updated.lat, 12.9);
      expect(updated.status, 'paused');
      expect(participantStatusLabel('reached'), 'Arrived');
    });

    test('friend request carries the other party', () {
      final f = FriendshipDto.fromJson({
        'id': 'f1',
        'requester_id': 'u2',
        'addressee_id': 'u1',
        'status': 'pending',
        'created_at': '2026-11-03T10:00:00Z',
        'user': _user,
      });
      expect(f.user?.username, 'alex');
    });

    test('search result friendship state', () {
      final r = UserSearchResultDto.fromJson({..._user, 'friendship': 'incoming'});
      expect(r.friendship, FriendshipState.incoming);
    });

    test('feed page with cursor and like result', () {
      final feed = PostFeedDto.fromJson({
        'posts': [
          {
            'id': 'p1',
            'author_id': 'u1',
            'author': _user,
            'like_count': 2,
            'comment_count': 1,
            'created_at': '2026-11-03T10:00:00Z',
            'images': [
              {'id': 'i1', 'file_path': 'posts/a.jpg', 'thumb_path': 'thumbnails/a.jpg', 'sort_order': 0},
            ],
            'liked_by_me': true,
          }
        ],
        'next_cursor': '2026-11-03T10:00:00.123Z',
      });
      expect(feed.posts.single.images.single.thumbPath, 'thumbnails/a.jpg');
      expect(feed.nextCursor, isNotNull);
      final like = LikeResultDto.fromJson({'liked': false, 'like_count': 1});
      expect(like.liked, isFalse);
    });

    test('shares list finds my active share', () {
      final list = LocationSharesListDto.fromJson({
        'mine': [
          {'id': 's0', 'owner_id': 'u1', 'duration': '1h', 'is_active': false},
          {
            'id': 's1',
            'owner_id': 'u1',
            'duration': 'indefinite',
            'is_active': true,
            'grants': [
              {'friend_user_id': 'u2', 'friend': _user, 'revoked_at': null},
            ],
          },
        ],
        'shared_with_me': [],
      });
      expect(list.activeMine?.id, 's1');
      expect(list.activeMine?.durationLabel, 'Until stopped');
      expect(list.activeMine?.grants.single.isActive, isTrue);
    });
  });

  group('errors', () {
    test('friendly messages', () {
      expect(friendlyError(ApiException(statusCode: 409, body: '{"detail":"username taken"}')),
          'username taken');
      expect(friendlyError(ApiException(statusCode: 502, body: '')),
          contains('trouble'));
      expect(isOfflineError(NetworkException('x')), isTrue);
    });
  });

  group('formatters', () {
    test('duration', () {
      expect(formatDuration(65), '01:05');
      expect(formatDuration(3725), '1:02:05');
    });
    test('distance', () {
      expect(formatDistanceMeters(850), '850 m');
      expect(formatDistanceMeters(2500), '2.5 km');
      expect(formatDistanceMeters(null), '—');
    });
  });
}
