# frozen_string_literal: true

FactoryBot.define do
  factory :artist do
    sequence(:name) { |n| "Artist #{n}" }
    sequence(:spotify_id) { |n| "spotify_artist_#{n}" }

    trait :with_image do
      image_url { "https://i.scdn.co/image/#{SecureRandom.hex(20)}" }
    end

    trait :with_metadata do
      metadata do
        {
          followers: rand(1000..1_000_000),
          popularity: rand(0..100),
        }
      end
    end

    trait :with_genre_metadata do
      transient do
        metadata_genre_names { ["thrash"] }
      end

      metadata { { "genres" => metadata_genre_names } }
    end

    trait :with_genres do
      transient do
        genres { [] }
      end

      after(:create) do |artist, evaluator|
        evaluator.genres.each { |genre| create(:artist_genre, artist: artist, genre: genre) }
      end
    end

    trait :in_library do
      transient do
        user { nil }
        current_version { nil }
      end

      after(:create) do |artist, evaluator|
        track = create(:track, :in_library, user: evaluator.user, current_version: evaluator.current_version)
        create(:track_artist, track: track, artist: artist)
      end
    end
  end
end
