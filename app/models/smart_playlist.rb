# frozen_string_literal: true

class SmartPlaylist < ApplicationRecord
  EVALUTATION_EXPIRES = 1.day

  belongs_to :user, inverse_of: :smart_playlists

  has_many :smart_playlist_sources, dependent: :destroy, inverse_of: :smart_playlist
  has_many :source_playlists, through: :smart_playlist_sources, source: :playlist

  belongs_to :target_playlist,
             class_name: "Playlist",
             optional: true,
             inverse_of: :smart_playlist_as_target

  validates :name, presence: true
  validates :name, uniqueness: { scope: :user_id }
  validates :rules, presence: true
  validate :rules_must_be_valid_structure

  scope :enabled, -> { where(is_enabled: true) }
  scope :needs_evaluation, lambda {
    enabled.where("last_evaluated_at IS NULL OR last_evaluated_at < ?", EVALUTATION_EXPIRES.ago)
  }

  private

  def rules_must_be_valid_structure
    return if rules.blank?
    return if rules.is_a?(Hash) && rules.key?("match") && rules.key?("rules")

    errors.add(:rules, "must have 'match' and 'rules' keys")
  end
end
