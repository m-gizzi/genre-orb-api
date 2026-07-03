# frozen_string_literal: true

FactoryBot.define do
  factory :playlist_version do
    playlist
    sequence(:version_number) { |n| n }
    track_ids { [] }
    track_count { 0 }

    trait :with_tracks do
      transient do
        tracks { [] }
      end

      track_ids { tracks.map(&:id) }
      track_count { tracks.count }
    end

    trait :snapshot do
      transient do
        from_playlist { nil }
      end

      after(:build) do |version, evaluator|
        if evaluator.from_playlist
          version.track_ids = evaluator.from_playlist.playlist_tracks.order(:position).pluck(:track_id)
          version.track_count = version.track_ids.count
        end
      end
    end
  end
end
