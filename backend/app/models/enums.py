"""Shared domain enums."""

import enum


class FriendshipStatus(str, enum.Enum):
    pending = "pending"
    accepted = "accepted"
    declined = "declined"
    blocked = "blocked"


class RideVisibility(str, enum.Enum):
    public = "public"
    private = "private"


class RideStatus(str, enum.Enum):
    scheduled = "scheduled"
    live = "live"
    ended = "ended"
    cancelled = "cancelled"


class ParticipantRole(str, enum.Enum):
    host = "host"
    participant = "participant"


class ParticipantStatus(str, enum.Enum):
    joined = "joined"
    on_the_way = "on_the_way"
    riding = "riding"
    paused = "paused"
    stopped = "stopped"
    reached = "reached"
    removed = "removed"
    left = "left"


class ShareDuration(str, enum.Enum):
    one_hour = "1h"
    eight_hours = "8h"
    indefinite = "indefinite"
