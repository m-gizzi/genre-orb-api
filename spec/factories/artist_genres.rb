# frozen_string_literal: true

FactoryBot.define do
  factory :artist_genre do
    artist
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
