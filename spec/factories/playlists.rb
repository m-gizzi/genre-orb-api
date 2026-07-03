# frozen_string_literal: true

FactoryBot.define do
  factory :playlist do
    user
    sequence(:name) { |n| "Playlist #{n}" }
    track_count { 0 }
    is_public { false }
    is_liked_songs { false }

    trait :liked_songs do
      name { "Liked Songs" }
      is_liked_songs { true }
    end

    trait :with_spotify do
      sequence(:spotify_id) { |n| "spotify_playlist_#{n}" }
      sequence(:snapshot_id) { |_n| "snapshot_#{SecureRandom.hex(8)}" }
    end

    trait :public do
      is_public { true }
    end

    trait :with_tracks do
      transient do
        tracks_count { 5 }
      end

      after(:create) do |playlist, evaluator|
        evaluator.tracks_count.times do |i|
          create(:playlist_track, playlist: playlist, track: create(:track), position: i)
        end
      end
    end
  end
end
