# frozen_string_literal: true

module Genres
  # What a genre means *for one user*, as a relation every read path can compose with.
  #
  #   1. source toggle    2. confidence floor    3. blocklist
  #   4. artist overlay   → projected onto tracks →   5. track overlay
  #
  # Applied in that order, each layer able to undo the one before it. There are no special
  # cases beyond the order itself.
  #
  # The result keeps the alias `track_genres` / `artist_genres`, so every existing
  # `joins(:genre)`, `where(track_genres: { … })` and `"track_genres.genre_id"` in the
  # codebase composes with it unchanged.
  class EffectiveScope
    def initialize(user, apply_blocklist: true)
      @user = user
      @apply_blocklist = apply_blocklist
    end

    def tracks
      return TrackGenre.all if tracks_neutral?

      TrackGenre.from(Arel.sql("(#{TrackGenreSql.new(user, preferences, overrides).call}) track_genres"))
    end

    def artists
      return ArtistGenre.all if artists_neutral?

      ArtistGenre.from(Arel.sql("(#{ArtistGenreSql.new(user, preferences, overrides).call}) artist_genres"))
    end

    def tracks_neutral?
      artists_neutral? && !overrides.any_track?
    end

    def artists_neutral?
      preferences.neutral? && !overrides.any_artist?
    end

    def preferences
      @preferences ||= Preferences.new(user, apply_blocklist: apply_blocklist)
    end

    private

    attr_reader :user, :apply_blocklist

    def overrides
      @overrides ||= Overrides.new(user)
    end
  end
end
