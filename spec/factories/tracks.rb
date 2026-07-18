# frozen_string_literal: true

FactoryBot.define do
  factory :track do
    sequence(:title) { |n| "Track #{n}" }
    sequence(:spotify_id) { |n| "spotify_track_#{n}" }
    album
    duration_ms { rand(120_000..360_000) } # 2-6 minutes
    track_number { 1 }
    explicit { false }
    popularity { rand(0..100) }

    trait :explicit do
      explicit { true }
    end

    trait :with_preview do
      preview_url { "https://p.scdn.co/mp3-preview/#{SecureRandom.hex(20)}" }
    end

    trait :in_library do
      transient do
        user { nil }
        current_version { nil }
      end

      after(:create) do |track, evaluator|
        version = evaluator.current_version
        unless version
          playlist = create(:playlist, user: evaluator.user || create(:user))
          version = create(:playlist_version, playlist: playlist)
          playlist.update!(current_version: version)
        end
        create(:playlist_version_track, playlist_version: version, track: track)
      end
    end

    trait :with_artists do
      transient do
        artist_count { 1 }
        artists { [] }
      end

      after(:create) do |track, evaluator|
        records = evaluator.artists.presence ||
                  Array.new(evaluator.artist_count) { create(:artist) }
        records.each do |artist|
          create(:track_artist, track: track, artist: artist)
        end
      end
    end

    trait :with_genres do
      transient do
        genre_names { [] }
        genres { [] }
      end

      after(:create) do |track, evaluator|
        evaluator.genre_names.each do |name|
          create(:track_genre, track: track, genre: Genre.find_or_create_by!(name: name))
        end
        evaluator.genres.each do |genre|
          create(:track_genre, track: track, genre: genre)
        end
      end
    end
  end
end
