# frozen_string_literal: true

module PlaylistVersions
  # Deletes one batch of versions, or none of it.
  #
  # The re-validation inside the lock is what makes this safe, not the foreign key.
  # Writing a reference to a version takes FOR KEY SHARE on it, which conflicts with our
  # FOR UPDATE: a session that got there first is skipped unlocked, one that committed
  # just before is caught by the re-read, and once we hold the row no new reference can
  # land until we commit. The FK is only the backstop, and losing one batch to it is
  # cheaper than losing the tick.
  class BatchDelete
    LOCK_CANDIDATES = <<~SQL.squish
      SELECT id FROM playlist_versions
      WHERE id IN (?)
      ORDER BY id
      FOR UPDATE SKIP LOCKED
    SQL

    LOCK_TIMEOUT_MS = 5_000
    STATEMENT_TIMEOUT_MS = 30_000

    CONFLICTS = [
      ActiveRecord::InvalidForeignKey,
      ActiveRecord::LockWaitTimeout,
      ActiveRecord::Deadlocked,
      ActiveRecord::QueryCanceled,
    ].freeze

    Result = Struct.new(:versions, :tracks, :conflicted, :contended, keyword_init: true) do
      def self.none(contended: 0)
        new(versions: 0, tracks: 0, conflicted: false, contended: contended)
      end

      def self.conflict
        new(versions: 0, tracks: 0, conflicted: true, contended: 0)
      end
    end

    def initialize(ids)
      @ids = ids
    end

    def call
      ActiveRecord::Base.transaction { purge }
    rescue *CONFLICTS => e
      Rails.logger.warn("PlaylistVersions::BatchDelete conflicted (#{e.class}): #{ids.inspect}")
      Result.conflict
    end

    private

    attr_reader :ids

    def purge
      SqlTimeout.apply(statement: STATEMENT_TIMEOUT_MS, lock: LOCK_TIMEOUT_MS)
      locked = locked_ids
      contended = ids.size - locked.size
      doomed = survivors(locked)
      return Result.none(contended: contended) if doomed.empty?

      SessionReferences.release(doomed)
      tracks = PlaylistVersionTrack.where(playlist_version_id: doomed).delete_all
      Result.new(
        versions: PlaylistVersion.where(id: doomed).delete_all,
        tracks: tracks,
        conflicted: false,
        contended: contended,
      )
    end

    def survivors(locked)
      return locked if locked.empty?

      pinned = SessionReferences.pinned_among(locked)
      current = Playlist.where(current_version_id: locked).pluck(:current_version_id).to_set
      locked.reject { |id| pinned.include?(id) || current.include?(id) }
    end

    def locked_ids
      PlaylistVersion.connection.select_values(
        ActiveRecord::Base.sanitize_sql_array([LOCK_CANDIDATES, ids]),
      )
    end
  end
end
