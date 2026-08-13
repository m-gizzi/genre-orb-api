# frozen_string_literal: true

FactoryBot.define do
  factory :smart_playlist do
    transient do
      user { association :user }
      source_count { 1 }
      source_playlists { [] }
    end

    target_playlist { association :playlist, :with_spotify, user: user }
    is_enabled { false }
    match_count { 0 }
    rules { SmartPlaylist::EMPTY_RULES.deep_dup }

    after(:build) do |smart_playlist, evaluator|
      next if smart_playlist.smart_playlist_sources.any?

      owner = smart_playlist.target_playlist.user
      playlists = evaluator.source_playlists.presence ||
                  Array.new(evaluator.source_count) { build(:playlist, user: owner) }

      playlists.each { |playlist| smart_playlist.smart_playlist_sources.build(playlist: playlist) }
    end

    trait :with_rules do
      rules do
        {
          "match" => "all",
          "rules" => [
            { "field" => "genre", "operator" => "equals", "value" => "rock" },
          ],
        }
      end
    end

    trait :enabled do
      with_rules
      is_enabled { true }
    end

    trait :liked_songs_source do
      transient do
        source_count { 0 }
      end

      after(:build) do |smart_playlist|
        smart_playlist.smart_playlist_sources.build(
          playlist: build(:liked_songs_playlist, user: smart_playlist.target_playlist.user),
        )
      end
    end

    trait :evaluated do
      with_rules
      last_evaluated_at { 1.hour.ago }
      match_count { rand(10..100) }
    end

    trait :pushed do
      evaluated
      last_pushed_at { 30.minutes.ago }
    end

    trait :playlist_rule do
      transient do
        excluded_playlist { association :playlist, :with_spotify, user: user, strategy: :create }
      end

      rules do
        {
          "match" => "all",
          "rules" => [
            { "field" => "playlist", "operator" => "not_in", "value" => [excluded_playlist.id] },
          ],
        }
      end
    end

    trait :complex_rules do
      rules do
        {
          "match" => "all",
          "rules" => [
            { "field" => "genre", "operator" => "contains", "value" => "metal" },
            { "field" => "year", "operator" => "greater_than", "value" => 2020 },
            {
              "match" => "any",
              "rules" => [
                { "field" => "artist", "operator" => "equals", "value" => "Artist A" },
                { "field" => "artist", "operator" => "equals", "value" => "Artist B" },
              ],
            },
          ],
        }
      end
    end
  end
end
