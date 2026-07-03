# frozen_string_literal: true

FactoryBot.define do
  factory :track do
    sequence(:title) { |n| "Track #{n}" }
    sequence(:spotify_id) { |n| "spotify_track_#{n}" }
    album
    duration_ms { rand(120_000..360_000) } # 2-6 minutes
    track_number { 1 }
    explicit { false }
    popularity { rand(0..100) }

    trait :explicit do
      explicit { true }
    end

    trait :with_preview do
      preview_url { "https://p.scdn.co/mp3-preview/#{SecureRandom.hex(20)}" }
    end

    trait :with_artists do
      transient do
        artist_count { 1 }
      end

      after(:create) do |track, evaluator|
        evaluator.artist_count.times do
          create(:track_artist, track: track, artist: create(:artist))
        end
      end
    end

    trait :with_genres do
      transient do
        genre_names { ["rock"] }
      end

      after(:create) do |track, evaluator|
        evaluator.genre_names.each do |name|
          genre = Genre.find_or_create_by!(name: name)
          create(:track_genre, track: track, genre: genre)
        end
      end
    end
  end
end
