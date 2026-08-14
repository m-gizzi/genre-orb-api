# frozen_string_literal: true

module Genres
  class Overrides
    def initialize(user)
      @user = user
      @flags = {}
    end

    def artist_hides? = flag(ArtistGenreOverride, :hidden)
    def artist_adds?  = flag(ArtistGenreOverride, :added)
    def track_hides?  = flag(TrackGenreOverride, :hidden)
    def track_adds?   = flag(TrackGenreOverride, :added)

    def any_artist? = artist_hides? || artist_adds?
    def any_track?  = track_hides? || track_adds?

    private

    attr_reader :user, :flags

    def flag(model, action)
      key = [model.name, action]
      return flags[key] if flags.key?(key)

      flags[key] = model.exists?(user: user, action: action)
    end
  end
end
