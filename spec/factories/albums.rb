# frozen_string_literal: true

FactoryBot.define do
  factory :album do
    sequence(:title) { |n| "Album #{n}" }
    sequence(:spotify_id) { |n| "spotify_album_#{n}" }
    release_year { rand(1960..Date.current.year) }
    total_tracks { rand(8..16) }

    trait :with_artwork do
      artwork_url { "https://i.scdn.co/image/#{SecureRandom.hex(20)}" }
    end

    trait :with_artists do
      transient do
        artist_count { 1 }
      end

      after(:create) do |album, evaluator|
        evaluator.artist_count.times do
          create(:album_artist, album: album, artist: create(:artist))
        end
      end
    end
  end
end
