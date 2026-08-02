# frozen_string_literal: true

module SmartPlaylists
  class Creator
    class MissingTargetError < StandardError; end

    attr_reader :user, :params

    def initialize(user, params)
      @user = user
      @params = params
    end

    def call
      smart_playlist = build_with_sources
      validate_sources!(smart_playlist)

      smart_playlist.target_playlist = resolve_target
      smart_playlist.save!
      smart_playlist
    end

    private

    def build_with_sources
      SmartPlaylist.new(rules: SmartPlaylist::EMPTY_RULES.deep_dup, is_enabled: false).tap do |smart_playlist|
        source_playlists.each { |playlist| smart_playlist.smart_playlist_sources.build(playlist: playlist) }
      end
    end

    def validate_sources!(smart_playlist)
      smart_playlist.validate
      raise ActiveRecord::RecordInvalid, smart_playlist if smart_playlist.errors[:source_playlists].any?
    end

    def source_playlists
      ids = Array(params[:source_playlist_ids]).map(&:to_i).uniq
      user.playlists.where(id: ids)
    end

    def resolve_target
      return user.playlists.find(params[:target_playlist_id]) if params[:target_playlist_id].present?
      return Spotify::PlaylistCreator.new(user, new_playlist_attributes).call if new_playlist_attributes.present?

      raise MissingTargetError
    end

    def new_playlist_attributes
      @new_playlist_attributes ||= params[:target_playlist_attributes].presence
    end
  end
end
