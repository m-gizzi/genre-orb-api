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
  validates :rules, presence: true, rule_set: true
  validate :target_must_exist_on_spotify
  validate :sources_must_be_present
  validate :sources_must_belong_to_owner
  validate :sources_must_not_create_a_cycle
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
    return if source_user_ids.all?(target_playlist.user_id)

    errors.add(:source_playlists, "must belong to the same user as the target playlist")
  end

  def source_user_ids
    assigned, stored = live_sources.partition { |source| source.association(:playlist).loaded? }

    assigned.map { |source| source.playlist&.user_id } +
      Playlist.where(id: stored.map(&:playlist_id)).pluck(:user_id)
  end

  def live_sources
    smart_playlist_sources.reject(&:marked_for_destruction?)
  end

  def sources_must_not_create_a_cycle
    return unless target_playlist

    graph = SmartPlaylists::DependencyGraph.new(target_playlist.user, excluding: id)
    looping = live_sources.map(&:playlist_id).select { |source_id| cycles_back?(graph, source_id) }
    return if looping.empty?

    errors.add(:source_playlists, cycle_message(looping))
  end

  def cycles_back?(graph, source_id)
    return false unless source_id && target_playlist_id

    graph.reaches?(target_playlist_id, source_id)
  end

  def cycle_message(looping)
    names = Playlist.where(id: looping).pluck(:name).sort
    subject = names.one? ? "it" : "them"
    "cannot include #{names.to_sentence} — this smart playlist already fills #{subject}, " \
      "directly or through a chain"
  end

  def rules_must_be_present_when_enabled
    return unless is_enabled
    return if ready?

    errors.add(:is_enabled, "cannot be turned on until at least one rule is added")
  end
end
