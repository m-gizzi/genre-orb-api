# frozen_string_literal: true

FactoryBot.define do
  factory :playlist do
    user
    sequence(:name) { |n| "Playlist #{n}" }

    trait :with_spotify do
      sequence(:spotify_id) { |n| "spotify_playlist_#{n}" }
      sequence(:last_seen_snapshot_id) { |_n| "snapshot_#{SecureRandom.hex(8)}" }
    end

    trait :sync_enabled do
      sync_enabled { true }
    end

    # A current version holding exactly the given tracks. Pass `memberships`
    # ([[track, added_at], ...]) when a spec cares about individual added_at
    # values, `tracks` when it does not.
    trait :holding do
      transient do
        tracks { [] }
        added_at { Time.current }
        memberships { nil }
        version_snapshot_id { nil }
      end

      after(:create) do |playlist, evaluator|
        rows = evaluator.memberships || evaluator.tracks.map { |track| [track, evaluator.added_at] }
        version = create(:playlist_version, playlist: playlist, status: :complete, track_count: rows.size,
                                            spotify_snapshot_id: evaluator.version_snapshot_id,)

        rows.each_with_index do |(track, added), index|
          create(:playlist_version_track,
                 playlist_version: version, track: track, position: index, added_at: added,)
        end

        playlist.update!(current_version: version)
      end
    end

    trait :with_tracks do
      transient do
        tracks_count { 5 }
      end

      after(:create) do |playlist, evaluator|
        version = create(:playlist_version, :with_tracks, playlist: playlist, tracks_count: evaluator.tracks_count)
        playlist.update!(current_version: version)
      end
    end
  end

  factory :liked_songs_playlist, parent: :playlist, class: "LikedSongsPlaylist" do
    name { "Liked Songs" }
  end
end
