# frozen_string_literal: true

FactoryBot.define do
  factory :artist_genre_override do
    user
    artist
    genre
    action { :hidden }

    trait :added do
      action { :added }
    end
  end
end
