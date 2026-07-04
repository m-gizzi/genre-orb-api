# frozen_string_literal: true

FactoryBot.define do
  factory :playlist_version do
    playlist
    sequence(:version_number) { |n| n }
    track_count { 0 }

    trait :with_tracks do
      transient do
        tracks_count { 5 }
      end

      after(:create) do |version, evaluator|
        evaluator.tracks_count.times do |i|
          create(:playlist_version_track, playlist_version: version, track: create(:track), position: i)
        end
        version.update!(track_count: evaluator.tracks_count)
      end
    end
  end
end
