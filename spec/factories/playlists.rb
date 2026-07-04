# frozen_string_literal: true

FactoryBot.define do
  factory :playlist do
    user
    sequence(:name) { |n| "Playlist #{n}" }
    is_public { false }

    trait :with_spotify do
      sequence(:spotify_id) { |n| "spotify_playlist_#{n}" }
      sequence(:snapshot_id) { |_n| "snapshot_#{SecureRandom.hex(8)}" }
    end

    trait :public do
      is_public { true }
    end

    trait :sync_enabled do
      sync_enabled { true }
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
