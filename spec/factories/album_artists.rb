# frozen_string_literal: true

FactoryBot.define do
  factory :album_artist do
    album
    artist
  end
end
