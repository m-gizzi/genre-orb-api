# frozen_string_literal: true

class TrackGenreOverride < ApplicationRecord
  include GenreOverridable

  belongs_to :user, inverse_of: :track_genre_overrides
  belongs_to :track

  validates :user_id, uniqueness: { scope: %i[track_id genre_id] }
end
