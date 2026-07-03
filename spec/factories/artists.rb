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
  end
end
