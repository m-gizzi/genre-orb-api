# frozen_string_literal: true

module GenreLoading
  extend ActiveSupport::Concern

  private

  def genre_loader
    @genre_loader ||= Genres::Loader.new(current_user)
  end

  def track_genres_for(tracks)
    { genres: genre_loader.for_tracks(tracks) }
  end

  def artist_genres_for(artists)
    { genres: genre_loader.for_artists(artists) }
  end
end
