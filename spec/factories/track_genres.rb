# frozen_string_literal: true

FactoryBot.define do
  factory :track_genre do
    track
    genre
    confidence { 1.0 }
    source { :spotify }

    trait :from_musicbrainz do
      source { :musicbrainz }
    end

    trait :from_lastfm do
      source { :lastfm }
    end
  end
end
