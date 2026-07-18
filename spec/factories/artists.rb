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
        genres { ["thrash"] }
      end

      metadata { { "genres" => genres } }
    end

    trait :in_library do
      transient do
        user { nil }
        current_version { nil }
        genres { [] }
      end

      after(:create) do |artist, evaluator|
        track = create(:track, :in_library, user: evaluator.user, current_version: evaluator.current_version)
        evaluator.genres.each { |genre| create(:track_genre, track: track, genre: genre) }
        create(:track_artist, track: track, artist: artist)
      end
    end
  end
end
