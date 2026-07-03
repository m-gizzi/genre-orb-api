# frozen_string_literal: true

class Genre < ApplicationRecord
  has_many :track_genres, dependent: :destroy, inverse_of: :genre
  has_many :tracks, through: :track_genres

  validates :name, presence: true, uniqueness: { case_sensitive: false }

  before_validation :normalize_name

  private

  def normalize_name
    return if name.blank?

    self.name = name.downcase.strip.gsub(/\s+/, " ")
  end
end
