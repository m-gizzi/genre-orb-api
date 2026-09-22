# frozen_string_literal: true

module PlaylistVersions
  module SessionReferences
    REFERENCES = [
      [PushSession, :playlist_version_id],
      [PushSession, :baseline_version_id],
      [SyncSessionPlaylist, :playlist_version_id],
      [SyncSessionPlaylist, :baseline_version_id],
    ].freeze

    class << self
      def pinned_ids
        REFERENCES.flat_map { |model, column| model.active.pluck(column) }.compact.to_set
      end

      def pinned_among(ids)
        REFERENCES.flat_map { |model, column| model.active.where(column => ids).pluck(column) }.compact
      end

      def release(ids)
        REFERENCES.each { |model, column| model.where(column => ids).update_all(column => nil) }
      end
    end
  end
end
