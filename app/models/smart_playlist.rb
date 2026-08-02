# frozen_string_literal: true

class SmartPlaylist < ApplicationRecord
  EVALUATION_EXPIRES = 1.day
  EMPTY_RULES = { "match" => "all", "rules" => [] }.freeze

  belongs_to :target_playlist,
             class_name: "Playlist",
             inverse_of: :smart_playlist_as_target

  has_many :smart_playlist_sources, dependent: :destroy, inverse_of: :smart_playlist
  has_many :source_playlists, through: :smart_playlist_sources, source: :playlist

  delegate :user, :user_id, :name, to: :target_playlist

  validates :target_playlist_id, uniqueness: true
  validates :rules, presence: true
  validate :rules_must_be_valid_structure
  validate :target_must_exist_on_spotify
  validate :sources_must_be_present
  validate :sources_must_belong_to_owner
  validate :rules_must_be_present_when_enabled

  after_create :enable_target_sync

  scope :enabled, -> { where(is_enabled: true) }
  scope :needs_evaluation, lambda {
    enabled.where("last_evaluated_at IS NULL OR last_evaluated_at < ?", EVALUATION_EXPIRES.ago)
  }

  def ready?
    rules.is_a?(Hash) && rules["rules"].present?
  end

  private

  def enable_target_sync
    target_playlist.update!(sync_enabled: true) unless target_playlist.sync_enabled?
  end

  def rules_must_be_valid_structure
    return if rules.blank?
    return if rules.is_a?(Hash) && rules.key?("match") && rules.key?("rules")

    errors.add(:rules, "must have 'match' and 'rules' keys")
  end

  def target_must_exist_on_spotify
    return if target_playlist.blank? || target_playlist.spotify_id.present?

    errors.add(:target_playlist, "must be a playlist that exists on Spotify")
  end

  def sources_must_be_present
    return if live_sources.any?

    errors.add(:source_playlists, "must include at least one playlist")
  end

  def sources_must_belong_to_owner
    return unless target_playlist

    owner_id = target_playlist.user_id
    return if live_sources.all? { |source| source.playlist&.user_id == owner_id }

    errors.add(:source_playlists, "must belong to the same user as the target playlist")
  end

  def live_sources
    smart_playlist_sources.reject(&:marked_for_destruction?)
  end

  def rules_must_be_present_when_enabled
    return unless is_enabled
    return if ready?

    errors.add(:is_enabled, "cannot be turned on until at least one rule is added")
  end
end
