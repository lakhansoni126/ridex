package service

import (
	"time"

	"github.com/google/uuid"
)

type User struct {
	ID          uuid.UUID `json:"id"`
	Email       string    `json:"email"`
	Username    string    `json:"username"`
	DisplayName string    `json:"display_name"`
	AvatarPath  *string   `json:"avatar_path"`
	Bio         *string   `json:"bio"`
	CreatedAt   time.Time `json:"created_at"`
}

func (u User) Public() UserPublic {
	return UserPublic{ID: u.ID, Username: u.Username, DisplayName: u.DisplayName, AvatarPath: u.AvatarPath}
}

type TokenOut struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	TokenType    string `json:"token_type"`
	User         User   `json:"user"`
}

type UserPublic struct {
	ID          uuid.UUID `json:"id"`
	Username    string    `json:"username"`
	DisplayName string    `json:"display_name"`
	AvatarPath  *string   `json:"avatar_path"`
}

type UserSearchResult struct {
	UserPublic
	Friendship string `json:"friendship"`
}

type UserStats struct {
	Friends     int `json:"friends"`
	RidesHosted int `json:"rides_hosted"`
	RidesJoined int `json:"rides_joined"`
	Posts       int `json:"posts"`
}

type GeoPoint struct {
	Lat float64 `json:"lat"`
	Lon float64 `json:"lon"`
}

type LocationPoint struct {
	Lat        float64   `json:"lat"`
	Lon        float64   `json:"lon"`
	SpeedMps   *float64  `json:"speed_mps"`
	Heading    *float64  `json:"heading"`
	AccuracyM  *float64  `json:"accuracy_m"`
	RecordedAt time.Time `json:"recorded_at"`
	Status     *string   `json:"status"`
}

type Participant struct {
	ID                     uuid.UUID   `json:"id"`
	RideID                 uuid.UUID   `json:"ride_id"`
	UserID                 uuid.UUID   `json:"user_id"`
	Role                   string      `json:"role"`
	Status                 string      `json:"status"`
	LastSeenAt             *time.Time  `json:"last_seen_at"`
	DistanceToHostM        *float64    `json:"distance_to_host_m"`
	DistanceToDestinationM *float64    `json:"distance_to_destination_m"`
	JoinedAt               time.Time   `json:"joined_at"`
	User                   *UserPublic `json:"user"`
	Lat                    *float64    `json:"lat"`
	Lon                    *float64    `json:"lon"`
}

type Ride struct {
	ID               uuid.UUID        `json:"id"`
	HostID           uuid.UUID        `json:"host_id"`
	Host             UserPublic       `json:"host"`
	Title            string           `json:"title"`
	Description      *string          `json:"description"`
	Visibility       string           `json:"visibility"`
	Status           string           `json:"status"`
	JoinCode         *string          `json:"join_code"`
	InviteToken      *string          `json:"invite_token"`
	ScheduledAt      *time.Time       `json:"scheduled_at"`
	StartedAt        *time.Time       `json:"started_at"`
	EndedAt          *time.Time       `json:"ended_at"`
	CreatedAt        time.Time        `json:"created_at"`
	UpdatedAt        time.Time        `json:"updated_at"`
	StartLat         *float64         `json:"start_lat"`
	StartLon         *float64         `json:"start_lon"`
	DestLat          *float64         `json:"dest_lat"`
	DestLon          *float64         `json:"dest_lon"`
	Waypoints        []map[string]any `json:"waypoints"`
	ParticipantCount int              `json:"participant_count"`
	IsParticipant    bool             `json:"is_participant"`
	Participants     []Participant    `json:"participants"`
}
