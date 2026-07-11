# frozen_string_literal: true

FactoryBot.define do
  factory :playlist_version_track do
    playlist_version
    track
    sequence(:position) { |n| n - 1 }
    added_at { Time.current }
  end
end
