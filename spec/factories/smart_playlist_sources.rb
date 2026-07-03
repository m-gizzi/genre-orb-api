# frozen_string_literal: true

FactoryBot.define do
  factory :smart_playlist_source do
    smart_playlist
    playlist { association :playlist, user: smart_playlist.user }
  end
end
