# frozen_string_literal: true

FactoryBot.define do
  factory :blocked_genre do
    user
    genre
  end
end
