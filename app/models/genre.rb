# frozen_string_literal: true

class Genre < ApplicationRecord
  has_many :track_genres, dependent: :destroy, inverse_of: :genre
  has_many :tracks, through: :track_genres

  validates :name, presence: true, uniqueness: { case_sensitive: false }

  before_validation :normalize_name

  def self.normalize_name(name)
    return nil if name.blank?

    name.downcase.strip.gsub(/\s+/, " ")
  end

  private

  def normalize_name
    self.name = self.class.normalize_name(name)
  end
end
