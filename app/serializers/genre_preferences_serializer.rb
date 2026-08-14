# frozen_string_literal: true

class GenrePreferencesSerializer
  def initialize(preferences)
    @preferences = preferences
  end

  def serializable_hash
    { sources: preferences.to_h, blocked_genres: blocked_genres }
  end

  private

  attr_reader :preferences

  def blocked_genres
    Genre.where(id: preferences.blocked_genre_ids)
         .order(:name)
         .map { |genre| { id: genre.id, name: genre.name } }
  end
end
