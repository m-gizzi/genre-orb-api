# frozen_string_literal: true

FactoryBot.define do
  factory :artist_metadata_source do
    artist
    source { :musicbrainz }
    state { :pending }

    trait :lastfm do
      source { :lastfm }
    end

    trait :matched do
      state { :matched }
      sequence(:external_id) { |n| "11111111-2222-3333-4444-#{n.to_s.rjust(12, "0")}" }
      attempted_at { Time.current }
    end

    trait :fetched do
      matched
      fetched_at { Time.current }
      retry_after { ArtistMetadataSource::REFRESH_TTL.from_now }
    end

    trait :unmatched do
      state { :unmatched }
      attempted_at { Time.current }
      retry_after { ArtistMetadataSource::UNMATCHED_RETRY.from_now }
    end

    trait :errored do
      state { :errored }
      attempted_at { Time.current }
      failure_count { 1 }
      last_error { "boom" }
      retry_after { 1.hour.from_now }
    end
  end
end
