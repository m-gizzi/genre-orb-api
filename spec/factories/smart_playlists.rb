# frozen_string_literal: true

FactoryBot.define do
  factory :smart_playlist do
    user
    sequence(:name) { |n| "Smart Playlist #{n}" }
    target_playlist { nil }
    is_enabled { true }
    match_count { 0 }
    rules do
      {
        "match" => "all",
        "rules" => [
          { "field" => "genre", "operator" => "equals", "value" => "rock" },
        ],
      }
    end

    trait :disabled do
      is_enabled { false }
    end

    trait :with_target do
      target_playlist { association :playlist, :with_spotify, user: user }
    end

    trait :evaluated do
      last_evaluated_at { 1.hour.ago }
      match_count { rand(10..100) }
    end

    trait :pushed do
      evaluated
      with_target
      last_pushed_at { 30.minutes.ago }
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

    trait :with_sources do
      transient do
        source_count { 1 }
      end

      after(:create) do |smart_playlist, evaluator|
        evaluator.source_count.times do
          create(:smart_playlist_source, smart_playlist: smart_playlist,
                                         playlist: create(:playlist, user: smart_playlist.user),)
        end
      end
    end
  end
end
