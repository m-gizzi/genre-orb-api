# frozen_string_literal: true

class BlockedGenre < ApplicationRecord
  belongs_to :user, inverse_of: :blocked_genres
  belongs_to :genre

  validates :user_id, uniqueness: { scope: :genre_id }
end
