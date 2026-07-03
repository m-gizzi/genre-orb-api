# frozen_string_literal: true

FactoryBot.define do
  factory :track_genre do
    track
    genre
    confidence { 1.0 }
    source { :spotify }

    trait :user_override do
      source { :user }
    end
  end
end
