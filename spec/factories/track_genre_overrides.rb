# frozen_string_literal: true

FactoryBot.define do
  factory :track_genre_override do
    user
    track
    genre
    action { :hidden }

    trait :added do
      action { :added }
    end
  end
end
