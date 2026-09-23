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
      # Only the live references among `ids`. Always ask about a bounded set: callers
      # hold a batch or a chunk's worth of candidates, and scoping the lookup keeps it on
      # the status indexes instead of dragging back every active session in the table.
      def pinned_among(ids)
        REFERENCES.flat_map { |model, column| model.active.where(column => ids).pluck(column) }.compact.to_set
      end

      # No `active` filter here, unlike `pinned_among`, and that asymmetry is the point:
      # callers must already have excluded everything a live session is holding. Nulling a
      # live pointer would strand the sync or push that is mid-flight. BatchDelete earns
      # the right to call this by re-reading `pinned_among` under the row lock first.
      def release(ids)
        REFERENCES.each { |model, column| model.where(column => ids).update_all(column => nil) }
      end
    end
  end
end
