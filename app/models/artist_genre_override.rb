# frozen_string_literal: true

class ArtistGenreOverride < ApplicationRecord
  include GenreOverridable

  belongs_to :user, inverse_of: :artist_genre_overrides
  belongs_to :artist

  validates :user_id, uniqueness: { scope: %i[artist_id genre_id] }
end
